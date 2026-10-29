import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/content_filter/promotion_evidence.dart';

void main() {
  for (final source in EvidenceSource.values) {
    test('uncertain OCR does not prevent a later ${source.name} match', () {
      final result = inspectPromotionEvidence([
        (
          Duration.zero,
          const [
            ContentEvidence(
              text: '赌场',
              source: EvidenceSource.screen,
              confidence: .6,
            ),
          ],
        ),
        (
          const Duration(milliseconds: 500),
          [ContentEvidence(text: '新葡京', source: source, confidence: .95)],
        ),
      ], const Duration(seconds: 20));
      expect(result.verdict, FilterVerdict.block);
      expect(result.ranges.single.start, const Duration(milliseconds: 500));
    });
  }
  test('weak evidence remains uncertain when no later positive exists', () {
    expect(
      inspectPromotionEvidence([
        (
          Duration.zero,
          const [
            ContentEvidence(
              text: '赌场',
              source: EvidenceSource.screen,
              confidence: .6,
            ),
          ],
        ),
        (
          const Duration(seconds: 1),
          const [ContentEvidence(text: '电影', source: EvidenceSource.speech)],
        ),
      ], const Duration(seconds: 20)).verdict,
      FilterVerdict.uncertain,
    );
  });
}
