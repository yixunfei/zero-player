import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_matcher.dart';
import 'package:zero_player/media/content_filter/fingerprints/sample_signature.dart';
import 'package:zero_player/media/content_filter/fingerprints/visual_fingerprint.dart';
import 'package:zero_player/media/content_filter/fingerprints/audio_fingerprint.dart';

void main() {
  test('informative spoken sample with pauses matches its own signature', () {
    final silence = List.filled(audioBands, 0);
    final speechA = List.generate(audioBands, (i) => i.isEven ? 220 : 20);
    final speechB = List.generate(audioBands, (i) => i.isOdd ? 200 : 30);
    final sound = [
      silence,
      silence,
      speechA,
      speechB,
      speechA,
      speechB,
      silence,
      silence,
    ];
    final rule = FeatureRule(
      id: 'voice',
      sourceId: 's',
      label: '口播',
      mode: FeatureMode.audio,
      sampleMs: 2000,
      beforeMs: 0,
      afterMs: 4000,
      visual: [],
      audio: sound,
      thumbnail: '',
      originKey: 'movie',
      originStartMs: 0,
    );
    rule.validate();
    final matcher = FeatureMatcher([rule]);
    expect(matcher.add(SampleSignature([], sound, ''), 0, 2000), hasLength(1));
    expect(
      FeatureMatcher([
        rule,
      ]).add(SampleSignature([], List.filled(8, silence), ''), 0, 2000),
      isEmpty,
    );
    expect(
      FeatureMatcher([rule]).add(
        SampleSignature([], [speechA, speechA, ...sound.skip(2)], ''),
        0,
        2000,
      ),
      isEmpty,
    );
  });
  test('a backwards timeline reset matches the same user feature again', () {
    const frame = VisualFingerprint('1234567890abcdef', [128, 50, 50], 30);
    final rule = FeatureRule(
      id: 'ad',
      sourceId: 'source',
      label: 'ad',
      mode: FeatureMode.visual,
      sampleMs: 2000,
      beforeMs: 0,
      afterMs: 4000,
      visual: List.filled(4, frame),
      audio: [],
      thumbnail: '',
      originKey: 'movie',
      originStartMs: 10000,
    );
    final matcher = FeatureMatcher([rule]);
    final sample = SampleSignature(List.filled(4, frame), [], '');
    expect(matcher.add(sample, 10000, 12000), hasLength(1));
    expect(matcher.add(sample, 12000, 14000), isEmpty);
    final repeated = matcher.add(sample, 0, 2000);
    expect(repeated, hasLength(1));
    expect(repeated.single.range.start, Duration.zero);
  });
}
