import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import '../../test_support/fake_player_engine.dart';

late AppServices services;
late Directory root;
late FakePlayerEngine engine;
late PlaybackController player;
final item = CatalogItem(
  sourceId: 'source',
  id: 'movie',
  title: 'Movie',
  lines: [
    PlayLine('main', [
      Episode('EP1', Uri.parse('https://example.org/1.mp4')),
      Episode('EP2', Uri.parse('https://example.org/2.mp4')),
    ]),
  ],
);

void main() {
  setUp(_initializeFixture);
  tearDown(() async {
    await player.close();
    await services.close();
    await root.delete(recursive: true);
  });
  test(
    'resume, pause persistence, and long press cancellation restore prior rate',
    () async {
      await player.open(
        PlaybackRequest(item, position: const Duration(seconds: 6)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(engine.seeks.last, const Duration(seconds: 6));
      await engine.setRate(1.5);
      await player.beginSpeed();
      expect(engine.snapshot.rate, 3);
      await player.endSpeed();
      await player.endSpeed();
      expect(engine.snapshot.rate, 1.5);
      await player.toggle();
      expect(
        (await services.history.all()).single.position,
        const Duration(seconds: 6),
      );
    },
  );
  test(
    'completion fires next episode once and respects autoplay setting',
    () async {
      await player.open(PlaybackRequest(item));
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 30),
          duration: Duration(seconds: 30),
          completed: true,
        ),
      );
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 30),
          duration: Duration(seconds: 30),
          completed: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(engine.opens, 2);
      expect(player.episode.label, 'EP2');
      await services.settings.update({'autoplay': false});
      await player.select(0, 0);
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 30),
          duration: Duration(seconds: 30),
          completed: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(player.episode.label, 'EP1');
    },
  );
  test('undo skip does not immediately skip the same interval again', () async {
    await services.skips.add(
      'source|movie|main|EP1',
      const Duration(seconds: 5),
      const Duration(seconds: 10),
      const Duration(seconds: 30),
      'opening',
    );
    await player.open(PlaybackRequest(item));
    engine.emit(
      const PlaybackSnapshot(
        position: Duration(seconds: 6),
        duration: Duration(seconds: 30),
        playing: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(engine.seeks.last, const Duration(seconds: 10));
    await player.undoSkip();
    expect(engine.seeks.last, const Duration(seconds: 6));
    expect(engine.seeks.length, 2);
  });
}

Future<void> _initializeFixture() async {
  root = await Directory.systemTemp.createTemp('zero-player-session-');
  services = AppServices.scoped(root, AppDatabase.memory());
  await services.settings.load();
  await services.gateway.start();
  engine = FakePlayerEngine();
  player = PlaybackController(services, engine);
}
