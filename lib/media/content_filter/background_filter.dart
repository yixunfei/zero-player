import 'dart:async';
import 'dart:io';
import '../../core/network/cancellation_token.dart';
import 'filter_types.dart';

typedef ProbeSample =
    Future<MediaSlice> Function(
      Uri,
      Duration,
      Duration,
      Directory,
      CancellationToken,
    );

/// One bounded worker. Detection never gates or substitutes the playback stream.
final class BackgroundFilter {
  BackgroundFilter({
    required this.input,
    required this.directory,
    required this.sample,
    required this.inspector,
    required this.onStatus,
    required this.onHit,
    this.onDiagnostic,
    this.start = Duration.zero,
    this.lookBehind = Duration.zero,
    this.overlap = Duration.zero,
  });
  final Uri input;
  final Directory directory;
  final ProbeSample sample;
  final SliceInspector inspector;
  final void Function(String) onStatus;
  final void Function(FilterDetection) onHit;
  final void Function(String)? onDiagnostic;
  final Duration start;
  final Duration lookBehind;
  final Duration overlap;
  final cancellation = CancellationToken();
  CancellationToken? _probe;
  Timer? _timer;
  Future<void>? _pending, _closing;
  bool _ready = false, _playing = false, _stopped = false;
  Duration _position = Duration.zero, _duration = Duration.zero;
  late Duration _cursor = _aligned(start - lookBehind);
  int _failures = 0;
  int _scanned = 0, _matched = 0, _late = 0;
  Duration _retryDelay = Duration.zero;
  int _epoch = 0;
  bool _resetInspector = false;
  Duration? _seekTarget;

  Duration get scanPosition => _cursor;
  Duration get playbackPosition => _position;

  void begin() {
    _pending = _prepare();
  }

  Future<void> _prepare() async {
    try {
      await directory.create(recursive: true);
      await inspector.prepare(cancellation);
      cancellation.check();
      _ready = true;
      onStatus('后台检测已启用 · 播放流畅优先');
    } catch (error) {
      _fail(error);
    } finally {
      _pending = null;
      _schedule();
    }
  }

  void observe(
    Duration position,
    Duration duration, {
    required bool playing,
    required bool buffering,
  }) {
    final target = _seekTarget;
    if (target != null) {
      if ((position - target).abs() > const Duration(milliseconds: 750)) {
        return;
      }
      _seekTarget = null;
    }
    if (position + const Duration(seconds: 2) < _position ||
        position > _position + const Duration(seconds: 8)) {
      // Native discontinuities and external seeks do not pass controller.seek.
      seek(position);
      _seekTarget = null;
    }
    _position = position;
    _duration = duration;
    _playing = playing && !buffering;
    _schedule();
  }

  void seek(Duration target) {
    _epoch++;
    _seekTarget = target;
    _resetInspector = true;
    _probe?.cancel();
    _timer?.cancel();
    _timer = null;
    _failures = 0;
    _retryDelay = Duration.zero;
    _cursor = _aligned(target - lookBehind);
    _position = target;
    onDiagnostic?.call('检测跟随跳转至 ${target.inMilliseconds / 1000} 秒，等待播放位置确认');
    _schedule();
  }

  void _schedule([Duration delay = const Duration(milliseconds: 400)]) {
    if (_stopped ||
        cancellation.isCancelled ||
        !_ready ||
        !_playing ||
        _seekTarget != null ||
        _pending != null ||
        _timer != null) {
      return;
    }
    _timer = Timer(delay, () {
      _timer = null;
      if (_playing && !cancellation.isCancelled) {
        _pending = Future<void>(_scan);
      }
    });
  }

  Future<void> _scan() async {
    final epoch = _epoch;
    final token = _probe = CancellationToken();
    final remove = cancellation.listen(token.cancel);
    Directory? work;
    final watch = Stopwatch()..start();
    try {
      if (_duration <= Duration.zero ||
          _cursor >= _duration ||
          _cursor > _position + const Duration(seconds: 12)) {
        return;
      }
      if (_cursor < _position - lookBehind - const Duration(seconds: 2)) {
        _cursor = _aligned(_position - lookBehind);
      }
      final window = const Duration(seconds: 4) + overlap;
      final length = _duration - _cursor < window
          ? _duration - _cursor
          : window;
      final from = _cursor;
      work = await directory.createTemp('probe_');
      final slice = await sample(input, from, length, work, token);
      token.check();
      if (_resetInspector) {
        if (inspector case final TemporalSliceInspector temporal) {
          temporal.reset();
        }
        _resetInspector = false;
      }
      final result = await inspector.inspect(slice, token);
      token.check();
      if (epoch != _epoch) return;
      if (_failures > 0) onStatus('后台检测已恢复 · 播放流畅优先');
      _failures = 0;
      _retryDelay = Duration.zero;
      _cursor = from + length;
      if (_cursor < _duration) _cursor -= overlap;
      _deliver(result);
      _scanned++;
      onDiagnostic?.call(
        '播放 ${_position.inMilliseconds / 1000} 秒 · 已扫描 $_scanned 段 · 本次 ${from.inMilliseconds / 1000}'
        '–${(from + length).inMilliseconds / 1000} 秒 · 耗时 ${watch.elapsedMilliseconds} ms\n'
        '内容命中 $_matched 次 · 已播过 $_late 次（不补跳后续内容）',
      );
    } catch (error) {
      if (!token.isCancelled && epoch == _epoch) {
        _failures++;
        _retryDelay = Duration(seconds: _failures.clamp(1, 5));
        onStatus('此段检测失败，正在自动重试 · 视频继续播放');
        onDiagnostic?.call(
          error is FilterFailure
              ? error.message
              : '采样或指纹处理失败（${error.runtimeType}）',
        );
        if (_failures >= 3) _cursor = _aligned(_position);
      }
    } finally {
      remove();
      if (work != null && await work.exists()) {
        try {
          await work.delete(recursive: true);
        } on FileSystemException {
          onStatus('检测临时文件清理失败 · 检测继续');
        }
      }
      _probe = null;
      _pending = null;
      _schedule(
        _retryDelay > Duration.zero
            ? _retryDelay
            : const Duration(milliseconds: 400),
      );
    }
  }

  void _deliver(FilterDecision result) {
    if (result.verdict == FilterVerdict.block) {
      for (final hit in result.resolvedDetections) {
        if (!hit.requiresConfirmation) _matched++;
        if (hit.range.end > _position) {
          onHit(hit);
        } else {
          _late++;
        }
      }
    } else if (result.verdict == FilterVerdict.uncertain) {
      onStatus('检测结果不确定 · 已继续播放');
    }
  }

  void _fail(Object error) {
    if (cancellation.isCancelled) return;
    _stopped = true;
    onStatus('检测暂不可用，已继续播放；请检查规则或识别资源');
  }

  Duration _aligned(Duration value) => Duration(
    milliseconds: (value.inMilliseconds ~/ 500 * 500).clamp(0, 86400000),
  );

  void cancel() {
    cancellation.cancel();
    _probe?.cancel();
    _timer?.cancel();
    _timer = null;
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    cancel();
    await _pending;
    await inspector.close();
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // The session is cancelled; a locked temporary file cannot block playback.
    }
  }
}
