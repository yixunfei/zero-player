import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import '../../test_support/fake_player_engine.dart';

late Directory root;
late AppServices services;
late FakePlayerEngine engine;
late PlaybackController player;

void _lifecycle() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('episode-mark-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.settings.load();
    await services.supervision.load();
    await services.gateway.start();
    engine = FakePlayerEngine();
    player = PlaybackController(services, engine);
    await player.open(_request('channel'));
    await player.seek(const Duration(seconds: 8));
    await _tick();
  });
  tearDown(() async {
    await player.close();
    await services.close();
    await root.delete(recursive: true);
  });
}

void main() {
  _lifecycle();
  test(
    'interval skips without samples, persists, undoes and repeats',
    () async {
      await services.settings.update({'skip': false});
      await services.skips.setWorkEnabled(player.seriesKey, false);
      await player.saveEpisodeMark(
        target: player.markTarget,
        start: const Duration(seconds: 5),
        end: const Duration(seconds: 12),
        label: '广告',
      );
      await _tick();
      expect(engine.seeks.last, const Duration(seconds: 12));
      expect(player.canUndoSkip, isTrue);
      expect(services.settings.value.skip, isTrue);
      expect(services.settings.value.contentFilter, isFalse);
      expect(await services.filterFeatures.list(), isEmpty);
      expect(await services.skips.list(player.workKey), hasLength(1));
      await player.undoSkip();
      await _tick();
      expect(engine.seeks.last, const Duration(seconds: 8));
      expect(player.canUndoSkip, isFalse);
      await player.seek(const Duration(seconds: 6));
      await _tick();
      expect(engine.seeks.last, const Duration(seconds: 12));
      await player.open(_request('channel'));
      await player.seek(const Duration(seconds: 6));
      await _tick();
      expect(engine.seeks.last, const Duration(seconds: 12));
      final id = player.marks.single.id;
      await services.skips.enable(id, false);
      await player.refreshSkipMarks();
      await player.seek(const Duration(seconds: 6));
      await _tick();
      expect(engine.seeks.last, const Duration(seconds: 6));
      await services.skips.remove(id);
      await player.refreshSkipMarks();
      expect(player.marks, isEmpty);
    },
  );
  test('paused mark keeps playback paused and applies on resume', () async {
    await engine.pause();
    await _tick();
    await player.saveEpisodeMark(
      target: player.markTarget,
      start: const Duration(seconds: 5),
      end: const Duration(seconds: 12),
      label: '广告',
    );
    expect(engine.snapshot.playing, isFalse);
    expect(engine.seeks.last, const Duration(seconds: 8));
    await engine.play();
    await _tick();
    expect(engine.seeks.last, const Duration(seconds: 12));
  });
  test(
    'stale dialog cannot write to switched source or reopened work',
    () async {
      final target = player.markTarget;
      await player.open(_request('other-channel'));
      await expectLater(
        player.saveEpisodeMark(
          target: target,
          start: const Duration(seconds: 5),
          end: const Duration(seconds: 12),
          label: '广告',
        ),
        throwsFormatException,
      );
      expect(await services.skips.list(player.workKey), isEmpty);
      expect(await services.skips.list(target.workKey), isEmpty);
      await player.open(_request('channel'));
      expect(() => player.checkMarkTarget(target), throwsFormatException);
    },
  );
  test('invalid endpoints do not create marks or enable settings', () async {
    await services.settings.update({'skip': false});
    await expectLater(
      player.saveEpisodeMark(
        target: player.markTarget,
        start: const Duration(seconds: 5),
        end: const Duration(seconds: 31),
        label: '广告',
      ),
      throwsFormatException,
    );
    expect(await services.skips.list(player.workKey), isEmpty);
    expect(services.settings.value.skip, isFalse);
  });
}

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 15));
PlaybackRequest _request(String channel) => PlaybackRequest(
  CatalogItem(
    sourceId: channel,
    id: 'work',
    title: '测试影片',
    lines: [
      PlayLine('main', [
        Episode('1', Uri.parse('https://example.org/movie.mp4')),
      ]),
    ],
  ),
);
