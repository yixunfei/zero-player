import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/platform/background_audio_session.dart';
import '../../playback/domain/player_engine.dart';
import '../data/music_repository.dart';
import '../domain/music_track.dart';
import '../data/music_library.dart';
import 'music_downloads.dart';
import '../../../media/gateway/offline_server.dart';

final class MusicController extends ChangeNotifier
    implements BackgroundAudioSession {
  MusicController(
    this.repository,
    this.createEngine, {
    this.beforePlay,
    this.libraryFactory,
    this.downloadsFactory,
    this.operationTimeout = const Duration(seconds: 25),
  }) {
    repository.policy?.addListener(_policyChanged);
  }
  final MusicRepository repository;
  final PlayerEngine Function() createEngine;
  final Future<void> Function()? beforePlay;
  final Duration operationTimeout;
  final MusicLibrary Function()? libraryFactory;
  final MusicDownloads Function()? downloadsFactory;
  MusicLibrary? _library;
  MusicDownloads? _downloads;
  MusicLibrary? get library => _library ??= libraryFactory?.call();
  MusicDownloads? get downloads => _downloads ??= downloadsFactory?.call();
  OfflineSession? _offline;
  DateTime _lastRecord = DateTime.fromMillisecondsSinceEpoch(0);
  final _visited = <int>{};
  MusicPlayMode get mode => library?.mode ?? _mode;
  MusicPlayMode _mode = MusicPlayMode.sequential;
  bool get hasNext =>
      active && (index + 1 < queue.length || mode != MusicPlayMode.sequential);
  Future<void> setMode(MusicPlayMode value) async {
    _mode = value;
    await library?.setMode(value);
    _visited.clear();
    if (!_closed) notifyListeners();
  }

  PlayerEngine? _engine;
  StreamSubscription<PlaybackSnapshot>? _states;
  StreamSubscription<String>? _errors;
  CancellationToken? _request;
  final _closing = Completer<void>();
  Completer<void>? _interrupt;
  Future<void> _pending = Future.value();
  Future<void>? _closeFuture;
  int _generation = 0;
  bool _closed = false;
  bool _needsOpen = false;
  List<MusicTrack> _queue = const [];
  List<MusicTrack> get queue => _queue;
  int index = -1;
  MusicTrack? get selected =>
      index < 0 || index >= queue.length ? null : queue[index];
  @override
  String get title => selected?.title ?? '';
  @override
  bool get active => selected != null && !_closed;
  @override
  bool loading = false;
  PlaybackSnapshot snapshot = const PlaybackSnapshot();
  @override
  bool get playing => snapshot.playing;
  String? error;
  double volume = 80;

  void _policyChanged() {
    if (selected != null && !repository.allowed(selected!)) {
      unawaited(stop());
      return;
    }
    final allowed = queue.where(repository.allowed).toList();
    if (allowed.length != queue.length) _replaceQueue(allowed);
  }

  void _replaceQueue(List<MusicTrack> tracks) {
    final key = selected?.key;
    _queue = List.unmodifiable(tracks);
    index = _queue.indexWhere((track) => track.key == key);
    _visited.clear();
    notifyListeners();
  }

  Future<void> enqueue(MusicTrack track, {bool playNext = false}) async {
    if (_closed) return;
    if (!repository.allowed(track)) throw const FormatException('歌曲已被过滤');
    if (!active) return select([track], 0);
    final existing = queue.indexWhere((item) => item.key == track.key);
    if (existing == index || (existing >= 0 && !playNext)) return;
    if (existing < 0 && queue.length >= 500) {
      throw const FormatException('播放队列最多 500 首');
    }
    final current = selected!.key;
    final tracks = queue.where((item) => item.key != track.key).toList();
    final currentIndex = tracks.indexWhere((item) => item.key == current);
    tracks.insert(playNext ? currentIndex + 1 : tracks.length, track);
    _replaceQueue(tracks);
  }

  void moveInQueue(String key, int delta) {
    if (_closed) return;
    final tracks = queue.toList();
    final from = tracks.indexWhere((track) => track.key == key);
    if (from < 0) return;
    final target = (from + delta).clamp(0, tracks.length - 1);
    tracks.insert(target, tracks.removeAt(from));
    _replaceQueue(tracks);
  }

  Future<void> removeFromQueue(String key) async {
    if (_closed) return;
    final from = queue.indexWhere((track) => track.key == key);
    if (from < 0) return;
    final remaining = queue.where((track) => track.key != key).toList();
    if (from != index) {
      _replaceQueue(remaining);
    } else if (remaining.isEmpty) {
      await stop();
    } else {
      await select(remaining, from.clamp(0, remaining.length - 1));
    }
  }

  void clearUpcoming() {
    if (!_closed && selected != null) _replaceQueue([selected!]);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.catchError((Object _) {});
    return next;
  }

  void _cancelSelection() {
    _request?.cancel();
    if (_interrupt?.isCompleted == false) _interrupt!.complete();
  }

  List<MusicTrack> _filteredQueue(List<MusicTrack> tracks) {
    final unique = <String, MusicTrack>{};
    for (final track in tracks.where(repository.allowed)) {
      unique.putIfAbsent(track.key, () => track);
    }
    if (unique.length > 500) throw const FormatException('播放队列最多 500 首');
    return List.unmodifiable(unique.values);
  }

  Future<void> select(
    List<MusicTrack> tracks,
    int selectedIndex, {
    bool refresh = false,
    Duration start = Duration.zero,
  }) {
    if (_closed || selectedIndex < 0 || selectedIndex >= tracks.length) {
      return Future.value();
    }
    final chosen = tracks[selectedIndex];
    if (!repository.allowed(chosen)) return Future.value();
    final filtered = _filteredQueue(tracks);
    unawaited(_record());
    if (!listEquals(
      queue.map((t) => t.key).toList(),
      filtered.map((t) => t.key).toList(),
    )) {
      _visited.clear();
    }
    _cancelSelection();
    final generation = ++_generation;
    final request = _request = CancellationToken();
    final interrupt = _interrupt = Completer<void>();
    _queue = filtered;
    index = queue.indexWhere((track) => track.key == chosen.key);
    loading = true;
    error = null;
    snapshot = const PlaybackSnapshot();
    _needsOpen = true;
    notifyListeners();
    return _enqueue(() async {
      if (_closed || generation != _generation) return;
      try {
        await _discardEngine();
        await _bounded(() async {
          await beforePlay?.call();
          if (_closed || generation != _generation) return;
          await library?.load();
          final local = await downloads?.open(chosen);
          if (_closed || generation != _generation) {
            local?.close();
            return;
          }
          _offline = local;
          final track = local == null
              ? await repository.resolve(chosen, request, refresh: refresh)
              : chosen.withUrl(local.uri);
          if (_closed || generation != _generation) return;
          if (!repository.allowed(track)) return;
          final engine = _engine = createEngine();
          _listen(engine, generation);
          await engine.setVolume(volume);
          if (_closed || generation != _generation) return;
          if (!repository.allowed(track)) return;
          await engine.open(
            track.url,
            headers: local == null ? repository.headers(track) : const {},
          );
          if (start > Duration.zero && !_closed && generation == _generation) {
            await engine.seek(start);
          }
          if (!_closed && generation == _generation && error == null) {
            _needsOpen = false;
          }
        }(), interrupt: interrupt.future);
      } catch (_) {
        if (!_closed && generation == _generation) {
          _playbackFailed('歌曲暂时无法播放，请重试或选择其他歌曲。');
          await _discardEngine();
        }
      } finally {
        if (!_closed && generation == _generation) {
          loading = false;
          notifyListeners();
        }
      }
    });
  }

  void _listen(PlayerEngine engine, int generation) {
    var completed = false;
    _states = engine.states.listen((state) {
      if (_closed || generation != _generation || _engine != engine) return;
      snapshot = state;
      if (state.playing &&
          state.position > Duration.zero &&
          DateTime.now().difference(_lastRecord) > const Duration(seconds: 5)) {
        _lastRecord = DateTime.now();
        _record();
      }
      notifyListeners();
      if (state.completed && !completed) {
        completed = true;
        unawaited(_advance(automatic: true));
      }
    });
    _errors = engine.errors.listen((_) {
      if (_closed || generation != _generation || _engine != engine) return;
      _playbackFailed('歌曲暂时无法播放，请重试或选择其他歌曲。');
      unawaited(_enqueue(_discardEngine));
    });
  }

  void _playbackFailed(String message) {
    ++_generation;
    _cancelSelection();
    loading = false;
    _needsOpen = true;
    error = message;
    snapshot = PlaybackSnapshot(
      position: snapshot.position,
      duration: snapshot.duration,
      volume: volume,
      rate: snapshot.rate,
    );
    notifyListeners();
  }

  Future<void> retry() => selected == null
      ? Future.value()
      : select(queue, index, refresh: true, start: snapshot.position);
  Future<void> next() => _advance();
  Future<void> _advance({bool automatic = false}) async {
    if (queue.isEmpty) return;
    final generation = _generation;
    await _record();
    if (_closed || generation != _generation) return;
    int target;
    if (automatic && mode == MusicPlayMode.repeatOne) {
      target = index;
    } else if (mode == MusicPlayMode.shuffle) {
      _visited.add(index);
      var candidates = [
        for (var i = 0; i < queue.length; i++)
          if (!_visited.contains(i)) i,
      ];
      if (candidates.isEmpty) {
        _visited.clear();
        candidates = [
          for (var i = 0; i < queue.length; i++)
            if (i != index || queue.length == 1) i,
        ];
      }
      target = candidates[Random().nextInt(candidates.length)];
    } else if (index + 1 < queue.length) {
      target = index + 1;
    } else if (mode == MusicPlayMode.repeatAll ||
        (!automatic && mode == MusicPlayMode.repeatOne)) {
      target = 0;
    } else {
      return;
    }
    if (!_closed) await select(queue, target);
  }

  Future<void> _record() async {
    final track = selected;
    if (track != null &&
        snapshot.duration > Duration.zero &&
        repository.allowed(track)) {
      try {
        await library?.record(track, snapshot);
      } catch (_) {
        /* Playback remains available if storage is full. */
      }
    }
  }

  Future<void> previous() => index > 0
      ? select(queue, index - 1)
      : mode == MusicPlayMode.repeatAll && queue.length > 1
      ? select(queue, queue.length - 1)
      : seek(Duration.zero);

  @override
  Future<void> toggle() {
    if (!active || loading) return Future.value();
    if (!repository.allowed(selected!)) return stop();
    if (_needsOpen) return retry();
    if (snapshot.completed) return select(queue, index);
    final generation = _generation;
    return _command((engine) async {
      if (!playing) await beforePlay?.call();
      if (_closed || generation != _generation || selected == null) return;
      if (!repository.allowed(selected!)) return;
      await engine.playOrPause();
    });
  }

  Future<void> pause() => _suspend(clear: false);
  @override
  Future<void> stop() => _suspend(clear: true);
  Future<void> _suspend({required bool clear}) {
    if (_closed) return Future.value();
    unawaited(_record());
    final retire = loading || clear;
    _cancelSelection();
    // Retire pending opens. Paused engines retain their state subscriptions.
    if (retire) ++_generation;
    loading = false;
    snapshot = PlaybackSnapshot(
      position: snapshot.position,
      duration: snapshot.duration,
      volume: volume,
    );
    if (retire) _needsOpen = true;
    if (clear) {
      _queue = const [];
      index = -1;
      error = null;
    }
    notifyListeners();
    return retire
        ? _enqueue(_discardEngine)
        : _command((engine) => engine.pause());
  }

  Future<void> seek(Duration position) => _command(
    (engine) => engine.seek(
      Duration(
        milliseconds: position.inMilliseconds.clamp(
          0,
          snapshot.duration.inMilliseconds,
        ),
      ),
    ),
  );
  Future<void> setVolume(double value) {
    volume = value.clamp(0, 100);
    if (!_closed) notifyListeners();
    return _command((engine) => engine.setVolume(volume));
  }

  Future<void> _command(Future<void> Function(PlayerEngine) action) {
    final generation = _generation;
    return _enqueue(() async {
      final engine = _engine;
      if (_closed || generation != _generation || engine == null) return;
      try {
        await _bounded(action(engine));
      } catch (_) {
        if (!_closed && generation == _generation) {
          _playbackFailed('播放操作失败，请重试。');
          await _discardEngine();
        }
      }
      if (!_closed) notifyListeners();
    });
  }

  Future<void> _bounded(Future<void> action, {Future<void>? interrupt}) =>
      Future.any([
        action,
        _closing.future,
        ?interrupt,
      ]).timeout(operationTimeout);

  Future<void> _discardEngine() async {
    final engine = _engine;
    _engine = null;
    _needsOpen = true;
    await _states?.cancel();
    await _errors?.cancel();
    _states = null;
    _errors = null;
    try {
      await engine?.dispose().timeout(const Duration(seconds: 2));
    } finally {
      _offline?.close();
      _offline = null;
    }
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    await _record();
    repository.policy?.removeListener(_policyChanged);
    _closed = true;
    ++_generation;
    _cancelSelection();
    _closing.complete();
    try {
      await _discardEngine();
    } finally {
      super.dispose();
    }
  }
}
