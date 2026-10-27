final class RemovedInterval {
  const RemovedInterval(this.start, this.end);
  final Duration start;
  final Duration end;
}

/// A single mapping shared by playback progress and filtered downloads.
final class MediaTimeline {
  const MediaTimeline(this.removed);
  final List<RemovedInterval> removed;
  Duration toOriginal(Duration processed) {
    var result = processed;
    for (final interval in removed) {
      if (result >= interval.start) result += interval.end - interval.start;
    }
    return result;
  }

  Duration toProcessed(Duration original) {
    var removedDuration = Duration.zero;
    for (final interval in removed) {
      if (original <= interval.start) break;
      removedDuration +=
          (original < interval.end ? original : interval.end) - interval.start;
    }
    return original - removedDuration;
  }
}
