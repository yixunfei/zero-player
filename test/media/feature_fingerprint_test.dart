import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import 'package:zero_player/features/settings/data/backup_validation.dart';
import 'package:zero_player/media/content_filter/fingerprints/audio_fingerprint.dart';
import 'package:zero_player/media/content_filter/fingerprints/visual_fingerprint.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_matcher.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_repository.dart';
import 'package:zero_player/media/content_filter/fingerprints/sample_signature.dart';

void main() {
  _algorithmTests();
  _ruleTests();
}

void _algorithmTests() {
  test(
    'visual fingerprint survives resize and JPEG, rejects unrelated frame',
    () {
      final source = _picture('CASINO 888', img.ColorRgb8(160, 20, 20));
      final copy = img.decodeJpg(
        img.encodeJpg(img.copyResize(source, width: 360), quality: 60),
      )!;
      final fingerprint = visualFingerprint(source);
      expect(fingerprint.informative, isTrue);
      expect(fingerprint.similarity(visualFingerprint(copy)), greaterThan(.92));
      expect(
        fingerprint.similarity(
          visualFingerprint(
            _picture('NATURE FILM', img.ColorRgb8(15, 120, 80)),
          ),
        ),
        lessThan(.92),
      );
      expect(
        visualFingerprint(img.Image(width: 32, height: 32)).informative,
        isFalse,
      );
    },
  );
  test(
    'spectral fingerprint tolerates volume and rejects unrelated sound and silence',
    () {
      final original = audioFingerprint(_wave());
      final quiet = audioFingerprint(_wave(gain: .25));
      final other = audioFingerprint(_wave(shift: 1900));
      expect(informativeAudio(original), isTrue);
      expect(_meanSimilarity(original, quiet), greaterThan(.99));
      expect(_meanSimilarity(original, other), lessThan(.94));
      expect(informativeAudio(audioFingerprint(Float64List(32000))), isFalse);
      expect(audioSimilarity(List.filled(24, 0), List.filled(24, 0)), 0);
    },
  );
  test(
    'a complete temporal sample matches across slice boundaries with offsets',
    () {
      final signature = visualFingerprint(
        _picture('CASINO 888', img.ColorRgb8(160, 20, 20)),
      );
      final rule = _rule(signature);
      final matcher = FeatureMatcher([rule]);
      expect(
        matcher.add(
          SampleSignature([signature, signature], [], ''),
          10000,
          11000,
        ),
        isEmpty,
      );
      final hits = matcher.add(
        SampleSignature([signature, signature], [], ''),
        11000,
        12000,
      );
      expect(hits, hasLength(1));
      expect(hits.single.range.start.inSeconds, 7);
      expect(hits.single.range.end.inSeconds, 27);
      expect(
        matcher.add(
          SampleSignature(List.filled(8, signature), [], ''),
          12000,
          16000,
        ),
        isEmpty,
      );
    },
  );
  test(
    'gaps do not fabricate continuous samples and both mode requires audio',
    () {
      final f = visualFingerprint(
        _picture('CASINO 888', img.ColorRgb8(160, 20, 20)),
      );
      final matcher = FeatureMatcher([_rule(f)]);
      matcher.add(SampleSignature([f, f], [], ''), 0, 1000);
      expect(matcher.add(SampleSignature([f, f], [], ''), 2000, 3000), isEmpty);
      final both = FeatureRule.fromJson({
        ..._rule(f).toJson(),
        'mode': 'both',
        'audio': audioFingerprint(_wave()),
      });
      expect(
        FeatureMatcher([
          both,
        ]).add(SampleSignature(List.filled(4, f), [], ''), 0, 2000),
        isEmpty,
      );
    },
  );
}

void _ruleTests() {
  test(
    'rules remain channel scoped and survive backup with supervision checks',
    () async {
      final db = AppDatabase.memory();
      var permitted = true;
      final repository = FeatureRepository(
        db,
        authorize: () {
          if (!permitted) throw StateError('locked');
        },
      );
      final f = visualFingerprint(
        _picture('CASINO 888', img.ColorRgb8(160, 20, 20)),
      );
      try {
        final rule = _rule(f);
        await repository.save(rule);
        expect(await repository.list(sourceId: 'other-channel'), isEmpty);
        expect(await repository.list(sourceId: rule.sourceId), hasLength(1));
        final exported = jsonDecode(await BackupService(db).export()) as Map;
        expect(jsonEncode(exported), contains('filter_feature:test-feature'));
        validateBackupRecord('app_meta', {
          'key': 'filter_feature:${rule.id}',
          'value': jsonEncode(rule.toJson()),
        });
        expect(
          () => validateBackupRecord('app_meta', {
            'key': 'filter_feature:wrong',
            'value': jsonEncode(rule.toJson()),
          }),
          throwsFormatException,
        );
        permitted = false;
        await expectLater(repository.setEnabled(rule, false), throwsStateError);
        await expectLater(repository.remove(rule.id), throwsStateError);
        expect((await repository.list()).single.enabled, isTrue);
      } finally {
        await db.close();
      }
    },
  );
  test('invalid empty and out-of-bounds feature payloads are rejected', () {
    final f = visualFingerprint(
      _picture('CASINO 888', img.ColorRgb8(160, 20, 20)),
    );
    for (final patch in [
      <String, Object>{'visual': []},
      {'beforeMs': 30001},
      {'afterMs': -1},
      {'thumbnail': 'invalid!'},
    ]) {
      expect(
        () => FeatureRule.fromJson({..._rule(f).toJson(), ...patch}),
        throwsFormatException,
      );
    }
  });
}

img.Image _picture(String text, img.Color background) {
  final image = img.Image(width: 640, height: 360);
  img.fill(image, color: background);
  img.drawRect(
    image,
    x1: 40,
    y1: 40,
    x2: 600,
    y2: 300,
    color: img.ColorRgb8(255, 255, 0),
    thickness: 8,
  );
  img.drawString(
    image,
    text,
    font: img.arial48,
    x: 80,
    y: 140,
    color: img.ColorRgb8(255, 255, 255),
  );
  return image;
}

Float64List _wave({double gain = 1, double shift = 0}) => Float64List.fromList(
  List.generate(32000, (i) {
    final t = i / 16000;
    final frequency = 250 + (i ~/ 4000) * 180 + shift;
    return gain *
        (.3 * math.sin(2 * math.pi * frequency * t) +
            .15 * math.sin(2 * math.pi * frequency * 2.7 * t));
  }),
);
double _meanSimilarity(List<List<int>> a, List<List<int>> b) =>
    List.generate(
      a.length,
      (i) => audioSimilarity(a[i], b[i]),
    ).reduce((a, b) => a + b) /
    a.length;
FeatureRule _rule(VisualFingerprint f) => FeatureRule(
  id: 'test-feature',
  sourceId: 'channel-one',
  label: 'ad',
  mode: FeatureMode.visual,
  sampleMs: 2000,
  beforeMs: 3000,
  afterMs: 15000,
  visual: List.filled(4, f),
  audio: [],
  thumbnail: '',
  originKey: 'episode',
  originStartMs: 10000,
);
