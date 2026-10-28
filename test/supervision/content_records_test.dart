import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/downloads/data/download_repository.dart';
import 'package:zero_player/features/library/data/history_repository.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/supervision_fixture.dart';

late SupervisionFixture f;
late Directory root;
late String sourceId;

void main() {
  setUp(() async {
    f = SupervisionFixture();
    await f.load();
    sourceId = await f.sources.saveManual(
      '普通来源',
      Uri.parse('https://example.org/api'),
    );
    await f.settings.update({'filterAdult': false});
    await f.configure();
    root = await Directory.systemTemp.createTemp('supervision-records-');
  });
  tearDown(() async {
    await f.close();
    await root.delete(recursive: true);
  });

  _recordCases();
  _epgCase();
}

void _recordCases() {
  test(
    'history and downloads preserve classification across filter changes',
    () async {
      final history = HistoryRepository(f.db, policy: f.policy);
      final downloads = DownloadRepository(f.db, root, policy: f.policy);
      final episode = Episode('1', Uri.parse('https://example.org/movie.mp4'));
      final line = PlayLine('线路', [episode]);
      final ordinary = CatalogItem(
        sourceId: sourceId,
        id: 'ordinary',
        title: '普通电影',
        category: '电影',
      );
      final restricted = CatalogItem(
        sourceId: sourceId,
        id: 'restricted',
        title: '普通标题',
        category: '倫理片',
      );
      for (final item in [ordinary, restricted]) {
        await history.save(
          item,
          line,
          episode,
          const Duration(seconds: 10),
          const Duration(minutes: 2),
        );
        await downloads.create(item, line, episode, {});
      }
      expect((await history.all()).length, 2);
      await f.settings.update({'filterAdult': true});
      expect((await history.all()).map((e) => e.remoteId), ['ordinary']);
      expect((await history.recentWorks()).map((e) => e.remoteId), [
        'ordinary',
      ]);
      final tasks = await downloads.all();
      expect(tasks.where(downloads.allowed).length, 1);
      final blocked = tasks.singleWhere(
        (t) => t.row['remote_id'] == 'restricted',
      );
      expect(
        () => downloads.requireAllowed(blocked),
        throwsA(isA<ContentBlocked>()),
      );
      await expectLater(
        downloads.create(restricted, line, episode, {}),
        throwsA(isA<ContentBlocked>()),
      );
      expect((await f.db.rows('SELECT id FROM watch_history')).length, 2);
      expect((await f.db.rows('SELECT id FROM downloads')).length, 2);
    },
  );

  test(
    'unclassified old history stays stored but hidden while filtering',
    () async {
      final history = HistoryRepository(f.db, policy: f.policy);
      final episode = Episode('1', Uri.parse('https://example.org/movie.mp4'));
      await history.save(
        CatalogItem(sourceId: sourceId, id: 'old', title: '旧记录'),
        PlayLine('线路', [episode]),
        episode,
        const Duration(seconds: 10),
        const Duration(minutes: 2),
      );
      await f.db.write("DELETE FROM app_meta WHERE key LIKE 'content_label:%'");
      expect(await history.all(), isEmpty);
      expect((await f.db.rows('SELECT id FROM watch_history')).length, 1);
      await history.recordSearch('演示关键词');
      await history.recordSearch('新闻');
      await f.authorized(
        SensitiveOperation.supervision,
        () => f.guard.updateRules(SupervisionRules(keywords: ['演示关键词'])),
      );
      expect(await history.searches(), ['新闻']);
    },
  );
}

void _epgCase() {
  test(
    'current EPG keywords block a neutral channel, expired entries do not',
    () async {
      final channel = LiveChannel(
        id: 'news',
        listId: 'list',
        name: '新闻频道',
        urls: [Uri.parse('https://example.org/news.mp4')],
      );
      f.policy.rememberChannels([channel]);
      await f.authorized(
        SensitiveOperation.supervision,
        () => f.guard.updateRules(SupervisionRules(keywords: ['受限节目'])),
      );
      final now = DateTime.now();
      f.policy.rememberPrograms(channel.name, [
        EpgProgram(
          'news',
          '受限节目',
          now.subtract(const Duration(minutes: 2)),
          now.add(const Duration(minutes: 2)),
        ),
      ]);
      expect(f.policy.liveNameAllowed(channel.name), isFalse);
      expect(
        () => f.policy.requireChannel(channel),
        throwsA(isA<ContentBlocked>()),
      );
      f.policy.rememberPrograms(channel.name, [
        EpgProgram(
          'news',
          '受限节目',
          now.subtract(const Duration(minutes: 4)),
          now.subtract(const Duration(minutes: 2)),
        ),
      ]);
      expect(f.policy.liveNameAllowed(channel.name), isTrue);
    },
  );
}
