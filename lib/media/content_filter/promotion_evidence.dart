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
  for (final (start, items) in evidence) {
    final result = policy.evaluate(items);
    if (result.verdict == FilterVerdict.block) {
      return FilterDecision(
        FilterVerdict.block,
        reason: result.reason,
        ranges: [RemovedInterval(start, start + span)],
      );
    }
    if (!result.allowed) uncertain = result;
  }
  return uncertain ?? const FilterDecision(FilterVerdict.allow);
}
