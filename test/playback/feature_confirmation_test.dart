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
    'confirmation, ignore, undo and episode changes respect current rules',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'feature-confirmation-',
      );
      final services = AppServices.scoped(root, AppDatabase.memory());
      final engine = FakePlayerEngine();
      final player = PlaybackController(services, engine);
      try {
        await services.settings.load();
        await services.supervision.load();
        await services.gateway.start();
        await services.settings.update({
          'contentFilter': true,
          'filterKeywords': false,
          'filterStrategy': 'confirm',
        });
        final item = CatalogItem(
          sourceId: 's',
          id: 'show',
          title: 'Show',
          lines: [
            PlayLine('main', [
              Episode('1', Uri.parse('https://example.org/1.mp4')),
              Episode('2', Uri.parse('https://example.org/2.mp4')),
            ]),
          ],
        );
        await player.open(PlaybackRequest(item));
        await services.filterFeatures.save(
          _rule(player.workKey, player.featureSeriesKey),
        );
        await player.refreshFeatureRules();
        await player.seek(const Duration(seconds: 6));
        await _settle();
        expect(engine.seeks.last, const Duration(seconds: 6));
        expect(player.pendingFeature, isNotNull);
        player.ignoreFeatureSkip();
        engine.change(position: const Duration(seconds: 7));
        await _settle();
        expect(player.pendingFeature, isNull);
        await player.seek(const Duration(seconds: 6));
        await _settle();
        player.confirmFeatureSkip();
        await _settle();
        expect(engine.seeks.last, const Duration(seconds: 12));
        await player.undoSkip();
        await _settle();
        expect(engine.seeks.last, const Duration(seconds: 6));
        expect(player.pendingFeature, isNull);
        await player.open(PlaybackRequest(item, episode: 1));
        await player.refreshFeatureRules();
        expect(player.activeFeatures, hasLength(1));
        await player.seek(const Duration(seconds: 6));
        await _settle();
        expect(player.pendingFeature, isNull);
        expect(engine.seeks.last, const Duration(seconds: 6));
        final rule = (await services.filterFeatures.list()).single;
        await services.filterFeatures.setEnabled(rule, false);
        await player.refreshFeatureRules();
        expect(player.activeFeatures, isEmpty);
      } finally {
        await player.close();
        await services.close();
        await root.delete(recursive: true);
      }
    },
  );
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));
FeatureRule _rule(String origin, String series) => FeatureRule(
  id: 'rule',
  sourceId: 's',
  label: '样本',
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
  originKey: origin,
  originStartMs: 5000,
  scope: FeatureScope.series,
  seriesKey: series,
);
