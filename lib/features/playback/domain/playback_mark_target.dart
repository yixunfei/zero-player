/// Identity captured when the editor opens. Reopening invalidates the editor.
final class PlaybackMarkTarget {
  const PlaybackMarkTarget({
    required this.generation,
    required this.workKey,
    required this.seriesKey,
    required this.sourceId,
    required this.duration,
  });
  final int generation;
  final String workKey, seriesKey, sourceId;
  final Duration duration;
}
