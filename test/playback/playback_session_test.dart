import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import 'package:zero_player/media/gateway/offline_server.dart';
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
  _regressionTests();
  _failedSeekRegression();
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
  services = AppServices.scoped(
    root,
    AppDatabase.memory(),
    allowPrivateNetworks: true,
  );
  await services.settings.load();
  await services.gateway.start();
  engine = FakePlayerEngine();
  player = PlaybackController(services, engine);
}

void _failedSeekRegression() {
  test('failed seek does not prevent rearming on a native reset', () async {
    await player.close();
    var failSeek = false;
    engine = FakePlayerEngine(
      onSeek: (_) async {
        if (failSeek) throw StateError('native seek failed');
      },
    );
    player = PlaybackController(services, engine);
    await services.skips.add(
      'source|movie|main|EP1',
      const Duration(seconds: 5),
      const Duration(seconds: 10),
      const Duration(seconds: 30),
      'advert',
    );
    await player.open(PlaybackRequest(item));
    await player.seek(const Duration(seconds: 6));
    await Future<void>.delayed(Duration.zero);
    expect(engine.seeks.last, const Duration(seconds: 10));
    failSeek = true;
    await expectLater(
      player.seek(const Duration(seconds: 20), rearmSkips: false),
      throwsStateError,
    );
    failSeek = false;
    engine.change(position: Duration.zero);
    await Future<void>.delayed(Duration.zero);
    engine.change(position: const Duration(seconds: 6));
    await Future<void>.delayed(Duration.zero);
    expect(engine.seeks.last, const Duration(seconds: 10));
    expect(engine.seeks.length, 4);
  });
}

void _regressionTests() {
  test(
    'manual rewind re-arms a mark while undo exempts only that visit',
    () async {
      await services.skips.add(
        'source|movie|main|EP1',
        const Duration(seconds: 5),
        const Duration(seconds: 10),
        const Duration(seconds: 30),
        'advert',
      );
      await player.open(PlaybackRequest(item));
      await player.seek(const Duration(seconds: 6));
      await Future<void>.delayed(Duration.zero);
      expect(engine.seeks.last, const Duration(seconds: 10));
      await player.undoSkip();
      await Future<void>.delayed(Duration.zero);
      expect(engine.seeks.last, const Duration(seconds: 6));
      await player.seek(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      engine.change(position: const Duration(seconds: 6));
      await Future<void>.delayed(Duration.zero);
      expect(engine.seeks.last, const Duration(seconds: 10));
    },
  );
  test(
    'filter enabled without channel features or models still opens and resumes',
    () async {
      await services.settings.update({'contentFilter': true});
      await player.open(
        PlaybackRequest(item, position: const Duration(seconds: 6)),
      );
      for (var i = 0; i < 100 && player.filterStatus == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(engine.opens, 1);
      expect(engine.snapshot.playing, isTrue);
      expect(engine.seeks.last, const Duration(seconds: 6));
      expect(player.error, isNull);
      expect(player.filterStatus, contains('未安装'));
      expect(
        Directory('${root.path}/content_filter/background').existsSync(),
        isFalse,
      );
    },
  );

  test('pause then resume does not disable later network recovery', () async {
    await player.open(PlaybackRequest(item));
    await Future<void>.delayed(Duration.zero);
    await player.toggle();
    await Future<void>.delayed(Duration.zero);
    await player.toggle();
    await Future<void>.delayed(Duration.zero);
    engine.failures.add('network');
    await Future<void>.delayed(Duration.zero);
    expect(player.recovering, isTrue);
  });

  test('offline retry retains its session and selected quality', () async {
    var closed = 0;
    final session = OfflineSession(
      Uri.parse('http://127.0.0.1/offline.mp4'),
      () => closed++,
    );
    final quality = Uri.parse('https://example.org/high.m3u8');
    await player.open(
      PlaybackRequest(item, offline: session, quality: quality),
    );
    await player.retry();
    expect(player.request!.offline, same(session));
    expect(player.request!.quality, quality);
    expect(closed, 0);
    await expectLater(player.select(0, 1), throwsFormatException);
    expect(player.request!.episode, 0);
  });

  test('seek is not reset to zero while duration is unknown', () async {
    await player.open(PlaybackRequest(item));
    engine.emit(const PlaybackSnapshot());
    await Future<void>.delayed(Duration.zero);
    await player.seek(const Duration(seconds: 12));
    expect(engine.seeks.last, const Duration(seconds: 12));
  });

  test('a failed progress save notifies immediately', () async {
    await player.open(PlaybackRequest(item));
    await services.db.customStatement('DROP TABLE watch_history');
    var notifications = 0;
    player.addListener(() => notifications++);
    await player.save();
    expect(player.notice, contains('进度保存失败'));
    expect(notifications, greaterThan(0));
  });
}
