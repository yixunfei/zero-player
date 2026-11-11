import 'dart:async';
import '../domain/player_engine.dart';

/// Native error streams include recoverable packet/decoder warnings. Only a
/// warning followed by no progress, or a sustained stall, is an interruption.
final class PlaybackHealth {
  PlaybackHealth({required this.onStalled, required this.onProgress});
  final void Function() onStalled;
  final void Function() onProgress;
  Timer? _warning;
  Timer? _watch;
  Duration _position = Duration.zero;
  bool _active = false;
  bool _reported = false;

  void observe(
    PlaybackSnapshot state, {
    required bool enabled,
    bool live = false,
  }) {
    if (!enabled || state.completed && !live) {
      reset();
      return;
    }
    if (!_active ||
        (_watch == null && (state.playing || state.buffering)) ||
        state.position > _position + const Duration(milliseconds: 200)) {
      _watch?.cancel();
      _watch = Timer(Duration(seconds: live ? 12 : 25), _stall);
      _position = state.position;
      if (_active && !state.buffering && state.playing) {
        _warning?.cancel();
        _warning = null;
        onProgress();
      }
      _reported = false;
    }
    // Track previews/capture also pause the engine without a user toggle.
    // Keep a pending native warning, but don't turn a quiet pause into a stall.
    if (!live && !state.playing && !state.buffering) {
      _watch?.cancel();
      _watch = null;
    }
    _active = true;
    if (live && state.completed) _stall();
  }

  void warn() {
    if (!_active || _reported || (_warning?.isActive ?? false)) return;
    _warning = Timer(const Duration(seconds: 3), _stall);
  }

  void _stall() {
    if (!_active || _reported) return;
    _reported = true;
    onStalled();
  }

  void reset() {
    _warning?.cancel();
    _watch?.cancel();
    _warning = _watch = null;
    _active = _reported = false;
    _position = Duration.zero;
  }

  void dispose() => reset();
}

String playbackFailureCategory(String text) {
  final value = text.toLowerCase();
  if (RegExp(r'decod|codec|mediacodec|surface|\bvo\b|\bvd\b').hasMatch(value)) {
    return '解码或画面输出';
  }
  if (RegExp(r'network|http|tcp|tls|timed? ?out|connection').hasMatch(value)) {
    return '网络或分片读取';
  }
  return '媒体读取';
}
