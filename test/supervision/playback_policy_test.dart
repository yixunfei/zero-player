import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/radio/application/radio_controller.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/fake_player_engine.dart';
import '../../test_support/supervision_fixture.dart';

void main() {
  _registerCase0();
  _registerCase1();
  _registerCase2();
}

void _registerCase0() {
  test(
    'live validates the selected channel rather than all lines or the title 直播',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'supervision-playback-',
      );
      final services = AppServices.scoped(root, AppDatabase.memory());
      final engine = FakePlayerEngine();
      final player = PlaybackController(services, engine);
      addTearDown(() async {
        await player.close();
        await services.close();
        await root.delete(recursive: true);
      });
      await services.supervision.load();
      await services.settings.load();
      await services.gateway.start();
      final news = LiveChannel(
        id: 'news',
        listId: 'list',
        name: '新闻',
        urls: [Uri.parse('https://example.org/news.mp4')],
      );
      final adult = LiveChannel(
        id: 'adult',
        listId: 'list',
        name: '普通名',
        group: '成人',
        urls: [Uri.parse('https://example.org/adult.mp4')],
      );
      services.contentPolicy.rememberChannels([news, adult]);
      final item = CatalogItem(
        sourceId: 'live',
        id: 'live',
        title: '直播',
        lines: [
          PlayLine(news.name, [Episode('1', news.urls.single)]),
          PlayLine(adult.name, [Episode('1', adult.urls.single)]),
        ],
      );
      await player.open(PlaybackRequest(item, live: true));
      expect(engine.opens, 1);
      expect(player.blocked, isFalse);
      await player.select(1, 0);
      expect(engine.opens, 1);
      expect(player.blocked, isTrue);
      expect(player.recovering, isFalse);
    },
  );
}

void _registerCase1() {
  test(
    'tightening the adult filter stops current playback and prevents resume',
    () async {
      final root = await Directory.systemTemp.createTemp('supervision-stop-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      final engine = FakePlayerEngine();
      final player = PlaybackController(services, engine);
      addTearDown(() async {
        await player.close();
        await services.close();
        await root.delete(recursive: true);
      });
      await services.supervision.load();
      await services.settings.load();
      await services.gateway.start();
      await services.settings.update({'filterAdult': false});
      final item = CatalogItem(
        sourceId: 'source',
        id: 'movie',
        title: '普通电影',
        category: '倫理片',
        lines: [
          PlayLine('main', [
            Episode('1', Uri.parse('https://example.org/movie.mp4')),
          ]),
        ],
      );
      await player.open(PlaybackRequest(item));
      expect(engine.opens, 1);
      await services.settings.update({'filterAdult': true});
      await Future<void>.delayed(Duration.zero);
      expect(player.blocked, isTrue);
      expect(engine.snapshot.playing, isFalse);
      await player.toggle();
      await player.retry();
      expect(engine.opens, 1);
      expect(player.recovering, isFalse);
      final blockedReason = player.error;
      engine.change(playing: true);
      engine.failures.add('late native event');
      await Future<void>.delayed(Duration.zero);
      expect(player.state.playing, isFalse);
      expect(player.error, blockedReason);
      expect(player.recovering, isFalse);
    },
  );
}

void _registerCase2() {
  test('blocked radio is stopped and tray toggle cannot restart it', () async {
    final f = SupervisionFixture();
    await f.configure();
    final engine = FakePlayerEngine();
    final radio = RadioController(() => engine, policy: f.policy);
    addTearDown(() async {
      await radio.close();
      await f.close();
    });
    final station = LiveChannel(
      id: 'r',
      listId: 'radio',
      name: '音乐电台',
      urls: [Uri.parse('https://example.org/radio.mp3')],
    );
    await radio.select(station);
    expect(engine.opens, 1);
    await f.authorized(
      SensitiveOperation.supervision,
      () => f.guard.updateRules(
        SupervisionRules(
          channels: [
            BlockedChannel(
              f.policy.channelKey(station.name, radio: true),
              station.name,
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(radio.selected, isNull);
    expect(engine.snapshot.playing, isFalse);
    await radio.toggle();
    expect(engine.snapshot.playing, isFalse);
    await expectLater(radio.select(station), throwsA(isA<ContentBlocked>()));
  });
}
