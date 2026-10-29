import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/content_filter/keyword_policy.dart';
import 'package:zero_player/media/content_filter/approved_timeline.dart';

void main() {
  const policy = KeywordPolicy();
  FilterDecision screen(String text, {double confidence = 0.95}) =>
      policy.evaluate([
        ContentEvidence(
          text: text,
          source: EvidenceSource.screen,
          confidence: confidence,
          heightRatio: 0.12,
        ),
      ]);

  test('prominent promotional text and traditional variants are blocked', () {
    for (final word in ['澳門', '新葡京', '緬北', '賭場', '真人', 'ＷＷＷ．abc.com']) {
      expect(screen(word).verdict, FilterVerdict.block, reason: word);
    }
  });
  test('ordinary geographic dialogue is not an advertisement', () {
    final result = policy.evaluate([
      const ContentEvidence(text: '明天去澳门参观博物馆', source: EvidenceSource.speech),
    ]);
    expect(result.allowed, isTrue);
  });
  test('uncertain keyword recognition never becomes an allow decision', () {
    expect(screen('新葡京', confidence: 0.5).verdict, FilterVerdict.uncertain);
    expect(screen('新葡京', confidence: double.nan).allowed, isFalse);
  });
  test('timeline maps a skipped gap and a seek origin exactly once', () {
    final timeline = ApprovedTimeline();
    timeline.add(const Duration(seconds: 100), const Duration(seconds: 4), 'a');
    timeline.add(const Duration(seconds: 112), const Duration(seconds: 4), 'b');
    expect(
      timeline.originalPosition(const Duration(seconds: 3)),
      const Duration(seconds: 103),
    );
    expect(
      timeline.originalPosition(const Duration(seconds: 4)),
      const Duration(seconds: 112),
    );
    expect(
      timeline.originalPosition(const Duration(seconds: 8)),
      const Duration(seconds: 116),
    );
  });
}
