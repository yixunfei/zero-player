import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/fingerprints/visual_fingerprint.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  test(
    'saving applies marked interval immediately and undo exempts this visit',
    () async {
      final root = await Directory.systemTemp.createTemp('saved-feature-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      final engine = FakePlayerEngine();
      final player = PlaybackController(services, engine);
      try {
        await services.settings.load();
        await services.supervision.load();
        await services.gateway.start();
        final item = CatalogItem(
          sourceId: 's',
          id: 'm',
          title: 'Movie',
          lines: [
            PlayLine('main', [
              Episode('1', Uri.parse('https://example.org/movie.mp4')),
            ]),
          ],
        );
        await player.open(PlaybackRequest(item));
        await player.seek(const Duration(seconds: 8));
        await Future<void>.delayed(Duration.zero);
        await services.filterFeatures.save(_rule(player.workKey));
        await services.settings.update({
          'contentFilter': true,
          'filterKeywords': false,
        });
        await player.refreshFeatureRules();
        for (var i = 0; i < 100 && !player.canUndoSkip; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(engine.seeks.last, const Duration(seconds: 12));
        expect(player.notice, contains('本集标记'));
        await player.undoSkip();
        await Future<void>.delayed(Duration.zero);
        expect(engine.seeks.last, const Duration(seconds: 8));
        expect(player.canUndoSkip, isFalse);
        await player.seek(const Duration(seconds: 6));
        await Future<void>.delayed(Duration.zero);
        expect(engine.seeks.last, const Duration(seconds: 12));
        await services.filterFeatures.remove('ad');
        await player.refreshFeatureRules();
        await player.seek(const Duration(seconds: 6));
        await Future<void>.delayed(Duration.zero);
        expect(engine.seeks.last, const Duration(seconds: 6));
      } finally {
        await player.close();
        await services.close();
        await root.delete(recursive: true);
      }
    },
  );
}

FeatureRule _rule(String key) => FeatureRule(
  id: 'ad',
  sourceId: 's',
  label: '手动广告',
  mode: FeatureMode.visual,
  sampleMs: 2000,
  beforeMs: 0,
  afterMs: 5000,
  visual: List.filled(
    4,
    const VisualFingerprint('1234567890abcdef', [128, 50, 50], 30),
  ),
  audio: [],
  thumbnail: '',
  originKey: key,
  originStartMs: 5000,
);
