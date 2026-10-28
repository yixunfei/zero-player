import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/platform/background_audio_session.dart';
import '../../live/domain/live_channel.dart';
import '../../playback/domain/player_engine.dart';

/// Serializes native player commands, discarding superseded station selections.
final class RadioController extends ChangeNotifier
    implements BackgroundAudioSession {
  RadioController(
    this.createEngine, {
    this.operationTimeout = const Duration(seconds: 20),
  });
  final PlayerEngine Function() createEngine;
  final Duration operationTimeout;
  final _closing = Completer<void>();
  Future<void>? _closeFuture;
  PlayerEngine? _engine;
  StreamSubscription<PlaybackSnapshot>? _states;
  StreamSubscription<String>? _errors;
  Future<void> _pending = Future<void>.value();
  int _generation = 0;
  bool _closed = false;
  Completer<void>? _selectionInterrupt;
  bool _needsOpen = false;
  @override
  bool loading = false;
  @override
  bool playing = false;
  bool buffering = false;
  double volume = 80;
  String? error;
  LiveChannel? selected;
  int line = 0;
  @override
  bool get active => selected != null && !_closed;
  @override
  String get title => selected?.name ?? '';

  PlayerEngine _player() {
    if (_engine case final engine?) return engine;
    final engine = _engine = createEngine();
    _states = engine.states.listen((state) {
      if (_closed || !identical(_engine, engine)) return;
      playing = state.playing;
      buffering = state.buffering;
      notifyListeners();
    });
    _errors = engine.errors.listen((_) {
      if (_closed || !identical(_engine, engine)) return;
      error = '电台暂时无法播放，请重试或选择其他线路/电台。';
      loading = false;
      notifyListeners();
    });
    return engine;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> select(LiveChannel station, {int lineIndex = 0}) {
    if (_closed || station.urls.isEmpty) return Future<void>.value();
    final retire = loading && _engine != null;
    final generation = ++_generation;
    _interruptSelection();
    final interrupt = _selectionInterrupt = Completer<void>();
    selected = station;
    line = lineIndex.clamp(0, station.urls.length - 1);
    final uri = station.urls[line];
    loading = true;
    playing = false;
    error = null;
    _needsOpen = false;
    notifyListeners();
    return _enqueue(() async {
      if (_closed || generation != _generation) return;
      try {
        if (retire) await _discardEngine();
        if (_closed || generation != _generation) return;
        final engine = _player();
        await _untilClosed(engine.stop(), interrupted: interrupt.future);
        if (_closed || generation != _generation) return;
        await _untilClosed(
          engine.setVolume(volume),
          interrupted: interrupt.future,
        );
        if (_closed || generation != _generation) return;
        await _untilClosed(
          engine.open(uri, headers: station.headersFor(uri)),
          interrupted: interrupt.future,
        );
        if (!_closed && generation == _generation) _needsOpen = false;
      } on TimeoutException {
        await _discardEngine();
        if (!_closed && generation == _generation) error = '电台连接超时，请重试或换台。';
      } catch (_) {
        if (!_closed && generation == _generation) error = '电台连接失败，请重试或换台。';
      } finally {
        if (!_closed && generation == _generation) {
          loading = false;
          notifyListeners();
        }
      }
    });
  }

  @override
  Future<void> toggle() {
    if (_needsOpen && selected != null) {
      return select(selected!, lineIndex: line);
    }
    return _command((engine) => engine.playOrPause());
  }

  Future<void> pause() => _suspend(clear: false);
  @override
  Future<void> stop() => _suspend(clear: true);

  Future<void> _suspend({required bool clear}) {
    if (_closed) return Future<void>.value();
    final retire = loading;
    ++_generation;
    _interruptSelection();
    loading = false;
    playing = false;
    buffering = false;
    if (retire) _needsOpen = true;
    if (clear) {
      selected = null;
      error = null;
    }
    notifyListeners();
    if (retire) return _enqueue(_discardEngine);
    return _command((engine) => clear ? engine.stop() : engine.pause());
  }

  void _interruptSelection() {
    final interrupt = _selectionInterrupt;
    if (interrupt != null && !interrupt.isCompleted) interrupt.complete();
  }

  Future<void> setVolume(double value) {
    if (_closed) return Future<void>.value();
    volume = value.clamp(0, 100);
    notifyListeners();
    return _command((engine) => engine.setVolume(volume));
  }

  Future<void> _command(Future<void> Function(PlayerEngine) operation) =>
      _enqueue(() async {
        if (_closed || _engine == null) return;
        try {
          await _untilClosed(operation(_engine!));
        } catch (_) {
          if (!_closed) error = '播放操作失败，请重新选择电台。';
        }
        if (!_closed) notifyListeners();
      });

  Future<void> _untilClosed(
    Future<void> operation, {
    Future<void>? interrupted,
  }) async {
    final expired = Completer<void>();
    final timer = Timer(
      operationTimeout,
      () =>
          expired.completeError(TimeoutException('Radio operation timed out')),
    );
    try {
      await Future.any([
        operation,
        expired.future,
        _closing.future,
        ?interrupted,
      ]);
    } finally {
      timer.cancel();
    }
  }

  Future<void> _discardEngine() async {
    _needsOpen = true;
    final engine = _engine;
    _engine = null;
    await _states?.cancel();
    await _errors?.cancel();
    _states = null;
    _errors = null;
    await engine?.dispose();
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    _interruptSelection();
    ++_generation;
    _closing.complete();
    await _states?.cancel();
    await _errors?.cancel();
    try {
      // Native disposal interrupts a pending open; waiting for it first deadlocks.
      await _engine?.dispose();
    } finally {
      super.dispose();
    }
  }
}
