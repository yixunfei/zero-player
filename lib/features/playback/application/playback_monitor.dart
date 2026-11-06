import 'dart:async';
import 'dart:io';
import '../domain/video_recovery_engine.dart';
import 'playback_controller.dart';
import 'playback_journal.dart';

final class PlaybackMonitor {
  PlaybackMonitor(this.player, Directory root, {required this.deviceSnapshot})
    : journal = PlaybackJournal(root);
  final PlaybackController player;
  final PlaybackJournal journal;
  final Future<Map<String, Object?>> Function() deviceSnapshot;
  Timer? _timer;
  bool _closed = false, _sampling = false;
  Future<void>? _starting;
  int _ticks = 0, _frozenFrames = 0;
  bool _hadVideo = false;
  bool _outputReported = false;
  Duration _position = Duration.zero;
  bool suspended = false;

  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    try {
      await journal.initialize();
      player.previousSessionReport = journal.previousReport;
      if (_closed) return;
      await _persist();
    } catch (_) {
      player.diagnostics.add('本机播放诊断暂时无法写入');
    }
    if (_closed) return;
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(sample()),
    );
    unawaited(sample());
  }

  Future<void> sample() async {
    if (_closed || _sampling) return;
    _sampling = true;
    try {
      player.runtimeDiagnostics['RSS MiB'] = (ProcessInfo.currentRss / 1048576)
          .round();
      player.runtimeDiagnostics['峰值 RSS MiB'] = (ProcessInfo.maxRss / 1048576)
          .round();
      if (_ticks++ % 3 == 0) {
        final device = await deviceSnapshot().timeout(
          const Duration(seconds: 2),
        );
        if (_closed) return;
        player.runtimeDiagnostics['Android 内存与历史退出'] = device;
      }
      final engine = player.engine is VideoRecoveryEngine
          ? player.engine as VideoRecoveryEngine
          : null;
      if (engine != null && !suspended) {
        final video = await engine.readVideoDiagnostics().timeout(
          const Duration(seconds: 3),
        );
        if (_closed) return;
        player.runtimeDiagnostics['解码与画面'] = video;
        _observeVideo(video);
      }
    } catch (_) {
      /* Diagnostics must never block playback or start recovery. */
    } finally {
      if (!_closed) await _persist();
      _sampling = false;
    }
  }

  void _observeVideo(Map<String, Object?> video) {
    final state = player.state;
    if (video['videoOutputFailed'] == true) {
      if (!_outputReported) player.reportVideoStall();
      _outputReported = true;
      return;
    }
    _outputReported = false;
    final configured = video['vo-configured'];
    if (_hadVideo &&
        configured == false &&
        state.playing &&
        !state.buffering &&
        !player.busy &&
        !suspended &&
        state.position > _position + const Duration(seconds: 1)) {
      if (++_frozenFrames == 3) player.reportVideoStall();
    } else {
      _frozenFrames = 0;
    }
    if (configured == true) _hadVideo = true;
    _position = state.position;
  }

  Future<void> _persist({bool closed = false}) async {
    try {
      await journal.write(
        player.diagnosticReport(includePrevious: false),
        closed: closed,
      );
    } catch (_) {
      /* Full storage must not interrupt decoding. */
    }
  }

  Future<void> close({bool clean = true}) async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await _starting;
    await _persist(closed: clean);
  }
}
