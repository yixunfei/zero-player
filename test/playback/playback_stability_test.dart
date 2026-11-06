import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import '../../test_support/fake_player_engine.dart';

late Directory root;
late AppServices services;
late FakePlayerEngine engine;
late PlaybackController player;
final item = CatalogItem(
  sourceId: 'fixture',
  id: 'movie',
  title: '稳定性样本',
  lines: [
    PlayLine('main', [Episode('1', Uri.parse('https://media.example/1.mp4'))]),
  ],
);

void main() {
  _resetOrderRegression();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('playback-stability-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.settings.load();
    await services.supervision.load();
    await services.gateway.start();
    engine = FakePlayerEngine();
    player = PlaybackController(services, engine);
  });
  tearDown(() async {
    await player.close();
    await services.close();
    await root.delete(recursive: true);
  });

  test(
    'a recoverable decoder warning does not interrupt advancing playback',
    () async {
      await player.open(PlaybackRequest(item));
      await player.seek(const Duration(seconds: 12));
      engine.failures.add(
        'decoder packet warning https://private.example/token',
      );
      await Future<void>.delayed(Duration.zero);
      engine.change(position: const Duration(seconds: 13));
      await Future<void>.delayed(Duration.zero);
      expect(player.error, isNull);
      expect(player.recovering, isFalse);
      expect(engine.opens, 1);
      expect(player.diagnosticReport(), isNot(contains('private.example')));
    },
  );

  test(
    'a short replacement resource never silently resumes at the beginning',
    () async {
      await player.open(
        PlaybackRequest(item, position: const Duration(minutes: 12)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(engine.seeks, isEmpty);
      expect(engine.snapshot.playing, isFalse);
      expect(player.error, contains('时长'));
      await player.save();
      expect(
        (await services.history.all()).single.position,
        const Duration(minutes: 12),
      );
    },
  );

  test(
    'an error burst preserves the position before a native position reset',
    () async {
      await player.open(PlaybackRequest(item));
      await player.seek(const Duration(seconds: 12));
      engine.failures.add('network');
      await Future<void>.delayed(Duration.zero);
      engine.emit(const PlaybackSnapshot());
      await Future<void>.delayed(const Duration(milliseconds: 3200));
      expect(player.recovering, isTrue);
      await player.save();
      expect(
        (await services.history.all()).single.position,
        const Duration(seconds: 12),
      );
    },
  );
}

void _resetOrderRegression() {
  test(
    'a native reset before its error still preserves the last good position',
    () async {
      await player.open(PlaybackRequest(item));
      await player.seek(const Duration(seconds: 12));
      engine.emit(const PlaybackSnapshot());
      await Future<void>.delayed(Duration.zero);
      engine.failures.add('network');
      await Future<void>.delayed(const Duration(milliseconds: 3200));
      expect(player.recovering, isTrue);
      await player.save();
      expect(
        (await services.history.all()).single.position,
        const Duration(seconds: 12),
      );
    },
  );
}
