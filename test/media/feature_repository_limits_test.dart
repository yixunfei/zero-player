import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_repository.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/fingerprints/visual_fingerprint.dart';

void main() {
  test('updating a rule cannot exceed its destination channel quota', () async {
    final db = AppDatabase.memory();
    final repository = FeatureRepository(db);
    try {
      for (var i = 0; i < 100; i++) {
        await repository.save(_rule('rule-$i', 'destination'));
      }
      await repository.save(_rule('moving', 'original'));
      await expectLater(
        repository.save(_rule('moving', 'destination')),
        throwsFormatException,
      );
      expect(await repository.list(sourceId: 'original'), hasLength(1));
      await repository.save(_rule('rule-0', 'destination'));
      await repository.remove('rule-0');
      await repository.save(_rule('moving', 'destination'));
      expect(await repository.list(sourceId: 'destination'), hasLength(100));
    } finally {
      await db.close();
    }
  });
}

FeatureRule _rule(String id, String source) => FeatureRule(
  id: id,
  sourceId: source,
  label: '样本',
  mode: FeatureMode.visual,
  sampleMs: 2000,
  beforeMs: 0,
  afterMs: 0,
  visual: List.filled(
    4,
    const VisualFingerprint('1234567890abcdef', [120, 60, 60], 30),
  ),
  audio: [],
  thumbnail: '',
  originKey: 'episode',
  originStartMs: 0,
);
