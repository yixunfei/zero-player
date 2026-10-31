import '../hls/timeline.dart';
import 'filter_types.dart';
import 'keyword_policy.dart';

/// A weak frame cannot hide clearer later frames or speech in the same slice.
FilterDecision inspectPromotionEvidence(
  Iterable<(Duration, Iterable<ContentEvidence>)> evidence,
  Duration span,
) {
  const policy = KeywordPolicy();
  FilterDecision? uncertain;
  final ranges = <RemovedInterval>[];
  String? reason;
  for (final (start, items) in evidence) {
    final result = policy.evaluate(items);
    if (result.verdict == FilterVerdict.block) {
      if (span > Duration.zero) {
        ranges.add(RemovedInterval(start, start + span));
      }
      reason ??= result.reason;
    }
    if (!result.allowed) uncertain = result;
  }
  if (ranges.isNotEmpty) {
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final merged = <RemovedInterval>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.start <= merged.last.end) {
        final previous = merged.removeLast();
        merged.add(
          RemovedInterval(
            previous.start,
            range.end > previous.end ? range.end : previous.end,
          ),
        );
      } else {
        merged.add(range);
      }
    }
    return FilterDecision(FilterVerdict.block, reason: reason!, ranges: merged);
  }
  return uncertain ?? const FilterDecision(FilterVerdict.allow);
}
