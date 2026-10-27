import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../live/domain/live_channel.dart';
import '../../playback/domain/player_engine.dart';

/// Serializes native player commands, discarding superseded station selections.
final class RadioController extends ChangeNotifier {
  RadioController(this.createEngine);
  final PlayerEngine Function() createEngine;
  PlayerEngine? _engine;
  StreamSubscription<PlaybackSnapshot>? _states;
  StreamSubscription<String>? _errors;
  Future<void> _pending = Future<void>.value();
  int _generation = 0;
  bool _closed = false;
  bool loading = false;
  bool playing = false;
  bool buffering = false;
  double volume = 80;
  String? error;
  LiveChannel? selected;
  int line = 0;
  bool get active => selected != null && !_closed;

  PlayerEngine _player() {
    if (_engine case final engine?) return engine;
    final engine = _engine = createEngine();
    _states = engine.states.listen((state) {
      if (_closed) return;
      playing = state.playing;
      buffering = state.buffering;
      notifyListeners();
    });
    _errors = engine.errors.listen((_) {
      if (_closed) return;
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
    final generation = ++_generation;
    selected = station;
    line = lineIndex.clamp(0, station.urls.length - 1);
    final uri = station.urls[line];
    loading = true;
    playing = false;
    error = null;
    notifyListeners();
    return _enqueue(() async {
      if (_closed || generation != _generation) return;
      try {
        final engine = _player();
        await engine.stop();
        if (_closed || generation != _generation) return;
        await engine.setVolume(volume);
        if (_closed || generation != _generation) return;
        await engine.open(uri, headers: station.headers);
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

  Future<void> toggle() => _command((engine) => engine.playOrPause());
  Future<void> stop() {
    ++_generation;
    loading = false;
    return _command((engine) => engine.stop());
  }

  Future<void> setVolume(double value) {
    volume = value.clamp(0, 100);
    return _command((engine) => engine.setVolume(volume));
  }

  Future<void> _command(Future<void> Function(PlayerEngine) operation) =>
      _enqueue(() async {
        if (_closed || _engine == null) return;
        try {
          await operation(_engine!);
        } catch (_) {
          if (!_closed) error = '播放操作失败，请重新选择电台。';
        }
        if (!_closed) notifyListeners();
      });

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_generation;
    await _states?.cancel();
    await _errors?.cancel();
    await _pending;
    await _engine?.dispose();
    super.dispose();
  }
}
