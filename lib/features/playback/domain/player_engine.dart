/// Player-independent control surface; presentation owns video rendering.
abstract interface class PlayerEngine {
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<String> get errors;
  Future<void> open(Uri uri, {Map<String, String> headers = const {}});
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> dispose();
  PlaybackSnapshot get snapshot;
  Stream<PlaybackSnapshot> get states;
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> setVolume(double volume);
  Future<List<int>?> screenshot();
}

final class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.rate = 1,
    this.volume = 100,
  });
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final bool completed;
  final double rate;
  final double volume;
}
