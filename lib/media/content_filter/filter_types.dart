import 'dart:io';

import '../../core/network/cancellation_token.dart';
import '../hls/timeline.dart';

enum FilterVerdict { allow, block, uncertain }

enum DetectionSource { feature, keyword }

final class FilterDetection {
  const FilterDetection(
    this.range,
    this.reason, {
    this.source = DetectionSource.feature,
  });
  final RemovedInterval range;
  final String reason;
  final DetectionSource source;
  bool get requiresConfirmation => source == DetectionSource.keyword;
}

enum EvidenceSource { speech, screen }

final class ContentEvidence {
  const ContentEvidence({
    required this.text,
    required this.source,
    this.confidence = 1,
    this.heightRatio = 0,
  });
  final String text;
  final EvidenceSource source;
  final double confidence;
  final double heightRatio;
}

final class FilterDecision {
  const FilterDecision(
    this.verdict, {
    this.reason = '',
    this.ranges = const [],
    this.detections = const [],
    this.requiresConfirmation = false,
  });
  final FilterVerdict verdict;
  final String reason;
  final List<RemovedInterval> ranges;
  final List<FilterDetection> detections;
  final bool requiresConfirmation;
  List<FilterDetection> get resolvedDetections => detections.isNotEmpty
      ? detections
      : ranges
            .map(
              (range) => FilterDetection(
                range,
                reason,
                source: requiresConfirmation
                    ? DetectionSource.keyword
                    : DetectionSource.feature,
              ),
            )
            .toList();
  bool get allowed => verdict == FilterVerdict.allow;
}

final class MediaSlice {
  const MediaSlice({
    required this.directory,
    required this.media,
    required this.frames,
    required this.audio,
    required this.start,
    required this.duration,
  });
  final Directory directory;
  final File media;
  final List<File> frames;
  final File? audio;
  final Duration start;
  final Duration duration;
}

abstract interface class SliceInspector {
  Future<void> prepare(CancellationToken cancellation);
  Future<FilterDecision> inspect(
    MediaSlice slice,
    CancellationToken cancellation,
  );
  Future<void> close();
}

/// Content remains quarantined until later samples cannot extend a match back
/// into it. This is required for user-configured before offsets.
abstract interface class DeferredSliceInspector implements SliceInspector {
  Duration get retention;
}

abstract interface class TemporalSliceInspector implements SliceInspector {
  void reset();
}

abstract interface class SliceSampler {
  Future<Duration> duration(Uri input, CancellationToken cancellation);
  Future<MediaSlice> sample(
    Uri input,
    Duration start,
    Duration duration,
    Directory directory,
    CancellationToken cancellation,
  );
  Future<File> publish(
    MediaSlice slice,
    Duration outputStart,
    CancellationToken cancellation,
  );
  Future<MediaSlice> crop(
    MediaSlice slice,
    Duration start,
    Duration length,
    CancellationToken cancellation,
  );
}

final class FilterFailure implements Exception {
  const FilterFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
