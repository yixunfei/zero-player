import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/platform/background_audio_session.dart';
import '../../settings/application/settings_controller.dart';
import '../../playback/domain/player_engine.dart';
import '../data/music_audio_probe.dart';
import '../data/music_repository.dart';
import '../domain/music_track.dart';
import '../domain/music_lyrics.dart';
import '../data/music_library.dart';
import 'music_downloads.dart';
import 'music_preflight.dart';
import '../../../media/gateway/offline_server.dart';

final class MusicController extends ChangeNotifier
    implements BackgroundAudioSession {
  MusicController(
    this.repository,
    this.createEngine, {
    this.beforePlay,
    this.libraryFactory,
    this.downloadsFactory,
    this.settings,
    MusicProbe? probe,
    this.stallTimeout = const Duration(seconds: 12),
    this.operationTimeout = const Duration(seconds: 25),
  }) : _preflight = MusicPreflight(repository, probe: probe) {
    _lastAutoPolicy = autoSwitchSource;
    repository.policy?.addListener(_policyChanged);
    settings?.addListener(_settingsChanged);
  }
  final MusicRepository repository;
  final PlayerEngine Function() createEngine;
  final Future<void> Function()? beforePlay;
  final Duration operationTimeout;
  final Duration stallTimeout;
  final SettingsController? settings;
  final MusicPreflight _preflight;
  final MusicLibrary Function()? libraryFactory;
  final MusicDownloads Function()? downloadsFactory;
  MusicLibrary? _library;
  MusicDownloads? _downloads;
  MusicLibrary? get library => _library ??= libraryFactory?.call();
  MusicDownloads? get downloads => _downloads ??= downloadsFactory?.call();
  OfflineSession? _offline;
  DateTime _lastRecord = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPreflight = DateTime.fromMillisecondsSinceEpoch(0);
  final _visited = <int>{};
  final _playNext = <String>[];
  Map<String, List<MusicTrack>> _queueVariants = const {};
  int? _shuffleNext;
  MusicPlayMode get mode => library?.mode ?? _mode;
  MusicPlayMode _mode = MusicPlayMode.sequential;
  bool get hasNext =>
      active &&
      (_playNext.isNotEmpty ||
          index + 1 < queue.length ||
          mode != MusicPlayMode.sequential);
  Future<void> setMode(MusicPlayMode value) async {
    _mode = value;
    await library?.setMode(value);
    _visited.clear();
    _shuffleNext = null;
    _prepareUpcoming();
    if (!_closed) notifyListeners();
  }

  bool _autoSwitchSource = false;
  late bool _lastAutoPolicy;
  bool get autoSwitchSource =>
      settings?.value.musicAutoFallback ?? _autoSwitchSource;
  String get _strategy => settings?.value.musicSourceStrategy ?? 'balanced';
  bool get _aggregationEnabled => settings?.value.musicAggregate ?? true;
  bool switchingSource = false;
  final _attemptedSources = <String>{};
  Future<void> setAutoSwitchSource(bool value) async {
    if (settings case final settings?) {
      await settings.update({'musicAutoFallback': value});
    } else {
      _autoSwitchSource = value;
      _settingsChanged();
    }
  }

  void _settingsChanged() {
    if (!autoSwitchSource) {
      _stall?.cancel();
      if (switchingSource && _automaticSwitch) _request?.cancel();
      if (_lastAutoPolicy || !_aggregationEnabled) _preflight.reset();
    } else if (_engine != null) {
      _watchStall(_generation, progressed: false);
    }
    _lastAutoPolicy = autoSwitchSource;
    _prepareUpcoming();
    if (!_closed) notifyListeners();
  }

  void prepareResults(Iterable<List<MusicTrack>> groups) {
    if (_closed || !_aggregationEnabled) return;
    for (final group in groups.where((group) => group.length > 1).take(8)) {
      unawaited(_preflight.prepare(group.first, alternatives: group.skip(1)));
    }
  }

  void prepareAddedTrack(MusicTrack track) {
    if (_closed || downloads?.localFor(track) != null) return;
    if (!autoSwitchSource && !_ranked(track)) return;
    unawaited(_prepareTrack(track));
  }

  bool _ranked(MusicTrack track) =>
      _aggregationEnabled && _queueVariants.containsKey(track.key);

  Future<void> _prepareTrack(MusicTrack track) async {
    await _preflight.prepare(
      track,
      alternatives: _ranked(track) ? _queueVariants[track.key]! : const [],
      findMatches: track.searchOnly,
    );
    if (!_closed && autoSwitchSource && _preflight.unavailable(track)) {
      await _preflight.prepare(track, findMatches: true);
    }
  }

  void _prepareUpcoming() {
    if ((!autoSwitchSource && !_aggregationEnabled) || index < 0) return;
    _lastPreflight = DateTime.now();
    final next = _nextIndex(automatic: true);
    for (final i in {?next, index + 1, index + 2}) {
      if (i < queue.length && i != index) prepareAddedTrack(queue[i]);
    }
  }

  bool _automaticSwitch = false;
  Future<void> switchSource({String? provider, bool automatic = false}) async {
    final original = selected;
    if (_closed ||
        original == null ||
        switchingSource ||
        (automatic && (!_wantsPlayback || !autoSwitchSource))) {
      return;
    }
    if (!automatic) _attemptedSources.clear();
    final generation = _generation;
    final position = snapshot.position;
    final wasPlaying = playing || error != null;
    final token = CancellationToken();
    _request?.cancel();
    _request = token;
    switchingSource = true;
    _automaticSwitch = automatic;
    _attemptedSources.add(playingTrack!.provider);
    notifyListeners();
    MusicAudioSample? replacement;
    try {
      if (original.artist.trim().isEmpty) {
        error = '缺少歌手信息，无法安全匹配其他渠道';
        return;
      }
      replacement = await _pickReplacement(original, token, provider: provider);
    } finally {
      switchingSource = false;
      if (!_closed) notifyListeners();
    }
    if (_closed || generation != _generation || token.isCancelled) return;
    if (replacement == null) {
      if (!playing) error = '未找到其他渠道的可播放版本';
      notifyListeners();
      return;
    }
    final opening = _select(
      queue,
      index,
      start: position,
      replacement: replacement.track,
    );
    final openedGeneration = _generation;
    await opening;
    if (!wasPlaying && openedGeneration == _generation && error == null) {
      await pause();
    }
  }

  Future<MusicAudioSample?> _pickReplacement(
    MusicTrack original,
    CancellationToken token, {
    String? provider,
  }) async {
    MusicAudioSample? best() => _preflight.best(
      original,
      _strategy,
      excludedProviders: _attemptedSources,
      provider: provider,
    );
    if (best() case final cached?) return cached;
    final cancelled = Completer<void>();
    final unlink = token.listen(cancelled.complete);
    final ready = Completer<void>();
    final updates = _preflight.updates.listen((_) {
      if (!ready.isCompleted && best() != null) ready.complete();
    });
    try {
      await Future.any([
        _preflight.prepare(original, findMatches: true, urgent: true),
        cancelled.future,
        ready.future,
      ]).timeout(const Duration(seconds: 10), onTimeout: () {});
      return token.isCancelled ? null : best();
    } finally {
      unlink();
      await updates.cancel();
    }
  }

  PlayerEngine? _engine;
  StreamSubscription<PlaybackSnapshot>? _states;
  StreamSubscription<String>? _errors;
  CancellationToken? _request;
  CancellationToken? _lyricsRequest;
  MusicLyrics _lyrics = MusicLyrics.empty;
  MusicLyrics lyrics = MusicLyrics.empty;
  bool get lyricsLoading => _lyricsRequest != null;
  final _closing = Completer<void>();
  Completer<void>? _interrupt;
  Future<void> _pending = Future.value();
  Future<void>? _closeFuture;
  int _generation = 0;
  bool _closed = false;
  bool _needsOpen = false;
  bool _wantsPlayback = false;
  Timer? _stall;
  MusicTrack? _playingTrack;
  MusicTrack? get playingTrack => _playingTrack ?? selected;
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
    _preflight.reset();
    if ((selected != null && !repository.allowed(selected!)) ||
        (playingTrack != null && !repository.allowed(playingTrack!))) {
      unawaited(stop());
      return;
    }
    final hadLyrics = lyrics.lines.isNotEmpty;
    lyrics = repository.visibleLyrics(_lyrics);
    final allowed = queue.where(repository.allowed).toList();
    if (allowed.length != queue.length) {
      _replaceQueue(allowed);
    } else if (hadLyrics || lyrics.lines.isNotEmpty) {
      notifyListeners();
    }
    _prepareUpcoming();
  }

  void _replaceQueue(List<MusicTrack> tracks) {
    final key = selected?.key;
    _queue = List.unmodifiable(tracks);
    index = _queue.indexWhere((track) => track.key == key);
    _visited.clear();
    _shuffleNext = null;
    _playNext.removeWhere((key) => !tracks.any((track) => track.key == key));
    _queueVariants = {
      for (final track in tracks) track.key: ?_queueVariants[track.key],
    };
    _prepareUpcoming();
    notifyListeners();
  }

  Future<void> enqueue(
    MusicTrack track, {
    bool playNext = false,
    List<MusicTrack> alternatives = const [],
  }) async {
    if (_closed) return;
    if (!repository.allowed(track)) throw const FormatException('歌曲已被过滤');
    final existing = queue.indexWhere((item) => item.key == track.key);
    if (existing >= 0 && (existing == index || !playNext)) return;
    if (existing < 0 && queue.length >= 500) {
      throw const FormatException('播放队列最多 500 首');
    }
    if (_aggregationEnabled && alternatives.isNotEmpty) {
      _queueVariants = {
        ..._queueVariants,
        track.key: List.unmodifiable(alternatives),
      };
    }
    prepareAddedTrack(track);
    if (!active) {
      _queue = List.unmodifiable([track]);
      index = 0;
      _needsOpen = true;
      notifyListeners();
      return;
    }
    final current = selected!.key;
    final tracks = queue.where((item) => item.key != track.key).toList();
    final currentIndex = tracks.indexWhere((item) => item.key == current);
    tracks.insert(playNext ? currentIndex + 1 : tracks.length, track);
    if (playNext) {
      _playNext.remove(track.key);
      _playNext.insert(0, track.key);
    }
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
      await select(
        remaining,
        from.clamp(0, remaining.length - 1),
        variants: _queueVariants,
      );
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
    _stall?.cancel();
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
    Map<String, List<MusicTrack>>? variants,
  }) => _select(
    tracks,
    selectedIndex,
    refresh: refresh,
    start: start,
    variants: variants,
  );

  Future<void> _select(
    List<MusicTrack> tracks,
    int selectedIndex, {
    bool refresh = false,
    Duration start = Duration.zero,
    Map<String, List<MusicTrack>>? variants,
    MusicTrack? replacement,
  }) {
    if (_closed || selectedIndex < 0 || selectedIndex >= tracks.length) {
      return Future.value();
    }
    final chosen = tracks[selectedIndex];
    if (!repository.allowed(chosen)) return Future.value();
    final filtered = _filteredQueue(tracks);
    if (replacement == null) _attemptedSources.clear();
    if (!identical(tracks, queue)) {
      _queueVariants = variants ?? const {};
      _playNext.clear();
    }
    unawaited(_record());
    if (!listEquals(
      queue.map((t) => t.key).toList(),
      filtered.map((t) => t.key).toList(),
    )) {
      _visited.clear();
    }
    _cancelSelection();
    _clearLyrics();
    final generation = ++_generation;
    final request = _request = CancellationToken();
    final interrupt = _interrupt = Completer<void>();
    _queue = filtered;
    index = queue.indexWhere((track) => track.key == chosen.key);
    _playNext.remove(chosen.key);
    _shuffleNext = null;
    _playingTrack = null;
    _wantsPlayback = true;
    loading = true;
    error = null;
    snapshot = const PlaybackSnapshot();
    _needsOpen = true;
    if (_ranked(chosen)) prepareAddedTrack(chosen);
    _prepareUpcoming();
    notifyListeners();
    return _enqueue(() async {
      if (_closed || generation != _generation) return;
      try {
        await _discardEngine();
        await _bounded(
          _openTrack(
            chosen,
            request,
            generation,
            replacement: replacement,
            refresh: refresh,
            start: start,
          ),
          interrupt: interrupt.future,
        );
      } catch (failure) {
        if (!_closed && generation == _generation) {
          _playbackFailed(
            failure is FormatException
                ? failure.message
                : '歌曲暂时无法播放，请重试或选择其他歌曲。',
          );
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

  Future<void> _openTrack(
    MusicTrack chosen,
    CancellationToken request,
    int generation, {
    required MusicTrack? replacement,
    required bool refresh,
    required Duration start,
  }) async {
    bool current() => !_closed && generation == _generation;
    await beforePlay?.call();
    if (!current()) return;
    await library?.load();
    final localTrack = downloads?.localFor(chosen)?.track ?? chosen;
    final local = replacement == null
        ? await downloads?.open(localTrack)
        : null;
    if (!current()) {
      local?.close();
      return;
    }
    _offline = local;
    final track = local != null
        ? localTrack.withUrl(local.uri)
        : replacement ?? await _resolve(chosen, request, refresh: refresh);
    if (!current()) return;
    if (!repository.allowed(track)) throw const FormatException('歌曲已被过滤');
    _playingTrack = track;
    if (local == null && repository.supportsLyrics(track)) {
      unawaited(_loadLyrics(track));
    }
    final engine = _engine = createEngine();
    _listen(engine, generation);
    await engine.setVolume(volume);
    if (!current() || !repository.allowed(track)) return;
    _watchStall(generation, progressed: true);
    await engine.open(
      track.url,
      headers: local == null ? repository.headers(track) : const {},
    );
    if (start > Duration.zero && current()) await engine.seek(start);
    if (current() && error == null) _needsOpen = false;
  }

  Future<MusicTrack> _resolve(
    MusicTrack chosen,
    CancellationToken token, {
    required bool refresh,
  }) async {
    final ranked = _ranked(chosen);
    final fallback = autoSwitchSource && _preflight.unavailable(chosen);
    if (!refresh) {
      final sample = chosen.searchOnly || ranked || fallback
          ? _preflight.best(chosen, _strategy)
          : autoSwitchSource
          ? _preflight.prepared(chosen)
          : null;
      if (sample != null) return sample.track;
    }
    if (chosen.searchOnly || (!refresh && fallback)) {
      final sample = await _pickReplacement(chosen, token);
      token.check();
      if (sample != null) return sample.track;
      if (chosen.searchOnly) throw const FormatException('未匹配到可播放的同名同歌手歌曲');
    }
    return repository.resolve(chosen, token, refresh: refresh);
  }

  void _clearLyrics() {
    _lyricsRequest?.cancel();
    _lyricsRequest = null;
    _lyrics = lyrics = MusicLyrics.empty;
  }

  Future<void> _loadLyrics(MusicTrack track) async {
    final token = _lyricsRequest = CancellationToken();
    final deadline = Timer(const Duration(seconds: 12), token.cancel);
    try {
      final result = await repository.lyrics(track, token);
      if (!token.isCancelled) {
        _lyrics = result;
        lyrics = repository.visibleLyrics(result);
      }
    } catch (_) {
      // Lyrics are optional and must never interrupt playback.
    } finally {
      deadline.cancel();
      if (!_closed && identical(_lyricsRequest, token)) {
        _lyricsRequest = null;
        notifyListeners();
      }
    }
  }

  void _listen(PlayerEngine engine, int generation) {
    var completed = false;
    _states = engine.states.listen((state) {
      if (_closed || generation != _generation || _engine != engine) return;
      final progressed = snapshot.position != state.position;
      snapshot = state;
      _watchStall(generation, progressed: progressed);
      if (progressed &&
          _wantsPlayback &&
          !state.completed &&
          DateTime.now().difference(_lastPreflight) >=
              const Duration(seconds: 20)) {
        _prepareUpcoming();
      }
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

  void _watchStall(int generation, {required bool progressed}) {
    if (!autoSwitchSource ||
        !_wantsPlayback ||
        snapshot.completed ||
        _offline != null) {
      _stall?.cancel();
      return;
    }
    if (progressed) _stall?.cancel();
    if (_stall?.isActive == true) return;
    _stall = Timer(stallTimeout, () {
      if (_closed ||
          generation != _generation ||
          !_wantsPlayback ||
          !autoSwitchSource) {
        return;
      }
      _playbackFailed('音乐缓冲超时，正在查找可用渠道。');
      unawaited(_enqueue(_discardEngine));
    });
  }

  void _playbackFailed(String message) {
    final failedTrack = _playingTrack;
    if (_offline == null && failedTrack != null && autoSwitchSource) {
      _preflight.markFailed(failedTrack);
    }
    ++_generation;
    _cancelSelection();
    _clearLyrics();
    loading = false;
    _needsOpen = true;
    error = message;
    if (autoSwitchSource &&
        _offline == null &&
        !switchingSource &&
        _wantsPlayback) {
      final failedGeneration = _generation;
      scheduleMicrotask(() {
        if (!_closed &&
            _generation == failedGeneration &&
            _wantsPlayback &&
            autoSwitchSource &&
            error == message) {
          unawaited(switchSource(automatic: true));
        }
      });
    }
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
    final target = _nextIndex(automatic: automatic);
    if (target != null) await select(queue, target);
  }

  int? _nextIndex({required bool automatic}) {
    if (_playNext.isNotEmpty) {
      final next = queue.indexWhere((track) => track.key == _playNext.first);
      if (next >= 0 && next != index) return next;
    }
    if (automatic && mode == MusicPlayMode.repeatOne) return index;
    if (mode == MusicPlayMode.shuffle) {
      if (_shuffleNext case final next?) return next;
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
      return _shuffleNext = candidates[Random().nextInt(candidates.length)];
    }
    if (index + 1 < queue.length) return index + 1;
    if (mode == MusicPlayMode.repeatAll ||
        (!automatic && mode == MusicPlayMode.repeatOne)) {
      return 0;
    }
    return null;
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
    if (_needsOpen) {
      return error == null
          ? select(queue, index, start: snapshot.position)
          : retry();
    }
    if (snapshot.completed) return select(queue, index);
    final generation = _generation;
    return _command((engine) async {
      final resume = !_wantsPlayback;
      if (resume) await beforePlay?.call();
      if (_closed || generation != _generation || selected == null) return;
      if (!repository.allowed(selected!)) return;
      _wantsPlayback = resume;
      _watchStall(generation, progressed: true);
      if (resume) {
        await engine.play();
      } else {
        await engine.pause();
      }
    });
  }

  Future<void> pause() => _suspend(clear: false);
  @override
  Future<void> stop() => _suspend(clear: true);
  Future<void> _suspend({required bool clear}) {
    if (_closed) return Future.value();
    unawaited(_record());
    final retire = loading || clear;
    _wantsPlayback = false;
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
      _clearLyrics();
      _preflight.reset();
      _playingTrack = null;
      _playNext.clear();
      _queueVariants = const {};
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
    settings?.removeListener(_settingsChanged);
    _clearLyrics();
    _closed = true;
    ++_generation;
    _cancelSelection();
    _closing.complete();
    try {
      await _preflight.close();
      await _discardEngine();
    } finally {
      super.dispose();
    }
  }
}
