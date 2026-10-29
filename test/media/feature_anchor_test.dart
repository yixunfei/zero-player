import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/content_filter/fingerprints/anchor_extraction.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_anchor.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_matcher.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/fingerprints/sample_signature.dart';

void main() {
  _sparseResumeTests();
  test('incomplete decoded tail preserves actual evidence without padding', () {
    final frames = _audio(15);
    final anchor = observedAnchor(
      SampleSignature([], frames, ''),
      offsetMs: 4000,
      requestedMs: 4000,
      mode: FeatureMode.audio,
    );
    expect(anchor.durationMs, 3500);
    expect(anchor.audio, frames.take(14));
    expect(anchor.offsetMs, 4000);
  });

  test('long capture scheduling is bounded and starts with early anchors', () {
    for (final length in [6500, 20000, 48000, 600000]) {
      final windows = anchorWindows(length);
      expect(windows.length, lessThanOrEqualTo(12));
      expect(windows.first, (0, 4000));
      expect(windows[1].$1, 4000);
      expect(windows.every((w) => w.$1 + w.$2 <= length), isTrue);
    }
  });

  test(
    'two aligned anchors relocate complete interval across probe boundaries',
    () {
      final rule = _rule();
      final restored = FeatureRule.fromJson(rule.toJson());
      final matcher = FeatureMatcher([restored]);
      expect(
        matcher.add(SampleSignature([], _audio(8), ''), 51000, 53000),
        isEmpty,
      );
      expect(
        matcher.add(const SampleSignature([], [], ''), 53000, 55000),
        isEmpty,
      );
      final hit = matcher
          .add(SampleSignature([], _audio(8, shift: 41), ''), 55000, 57000)
          .single;
      expect(hit.range.start.inMilliseconds, 51000);
      expect(hit.range.end.inMilliseconds, 81000);
      expect(restored.sampleMs, 30000);
      expect(restored.signatures.length, 2);
    },
  );

  test(
    'inconsistent anchor positions and seek history never infer a long skip',
    () {
      final matcher = FeatureMatcher([_rule()]);
      matcher.add(SampleSignature([], _audio(8), ''), 51000, 53000);
      matcher.add(const SampleSignature([], [], ''), 53000, 56000);
      expect(
        matcher.add(
          SampleSignature([], _audio(8, shift: 41), ''),
          56000,
          58000,
        ),
        isEmpty,
      );
      matcher.reset();
      expect(
        matcher.add(
          SampleSignature([], _audio(8, shift: 41), ''),
          55000,
          57000,
        ),
        isEmpty,
      );
    },
  );
  _repeatedContentTest();
}

void _sparseResumeTests() {
  test(
    'sparse and missing tail anchors retain two pieces of resume evidence',
    () {
      for (final (duration, offsets) in [
        (120000, [0, 4000, 116000]),
        (600000, [0, 4000]),
      ]) {
        final rule = FeatureRule.fromJson({
          ..._rule().toJson(),
          'sampleMs': duration,
          'anchors': [
            for (final (i, offset) in offsets.indexed)
              FeatureAnchor(
                offsetMs: offset,
                durationMs: 4000,
                visual: [],
                audio: _audio(16, shift: i * 41),
              ).toJson(),
          ],
        });
        expect(rule.reacquireMs, greaterThanOrEqualTo(duration - 4000));
        final resume = duration - 10000;
        final from = (resume - rule.reacquireMs).clamp(0, duration);
        final matcher = FeatureMatcher([rule]);
        final hits = <FeatureHit>[];
        for (final anchor in rule.signatures.where((a) => a.offsetMs >= from)) {
          hits.addAll(
            matcher.add(
              SampleSignature([], anchor.audio, ''),
              anchor.offsetMs,
              anchor.offsetMs + anchor.durationMs,
            ),
          );
        }
        expect(hits.first.range.end.inMilliseconds, duration);
      }
    },
  );
}

void _repeatedContentTest() {
  test(
    'repeated content chooses earliest supported boundary across all anchors',
    () {
      final a = _audio(16), b = _audio(16, shift: 41);
      final rule = FeatureRule(
        id: 'repeated',
        sourceId: 'channel',
        label: 'Repeated speech',
        mode: FeatureMode.audio,
        sampleMs: 16000,
        beforeMs: 0,
        afterMs: 0,
        visual: [],
        audio: [],
        thumbnail: '',
        originKey: 'first',
        originStartMs: 5000,
        anchors: [
          for (var i = 0; i < 4; i++)
            FeatureAnchor(
              offsetMs: i * 4000,
              durationMs: 4000,
              visual: [],
              audio: i.isEven ? a : b,
            ),
        ],
      );
      final matcher = FeatureMatcher([rule]);
      // Resume inside content: the first visible anchor is the second one.
      expect(matcher.add(SampleSignature([], b, ''), 307000, 311000), isEmpty);
      expect(
        matcher
            .add(SampleSignature([], a, ''), 311000, 315000)
            .single
            .range
            .end,
        const Duration(seconds: 319),
      );
    },
  );
}

List<List<int>> _audio(int count, {int shift = 0}) => List.generate(
  count,
  (i) => List.generate(24, (band) => (i * 71 + band * 29 + shift) % 256),
);

FeatureRule _rule() => FeatureRule(
  id: 'long',
  sourceId: 'channel',
  label: '完整广告',
  mode: FeatureMode.audio,
  sampleMs: 30000,
  beforeMs: 0,
  afterMs: 0,
  visual: [],
  audio: [],
  thumbnail: '',
  originKey: 'first',
  originStartMs: 123137,
  anchors: [
    FeatureAnchor(offsetMs: 0, durationMs: 2000, visual: [], audio: _audio(8)),
    FeatureAnchor(
      offsetMs: 4000,
      durationMs: 2000,
      visual: [],
      audio: _audio(8, shift: 41),
    ),
  ],
);
