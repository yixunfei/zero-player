import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/domain/channel_identity.dart';
import 'package:zero_player/features/live/domain/channel_order.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';

void main() {
  test(
    'known CCTV aliases merge without collapsing sports-plus or region feeds',
    () {
      for (final name in ['CCTV-1', 'CCTV-1 综合', 'cctv1综合高清', '央视1', '中央1台']) {
        expect(channelIdentity(name), 'CCTV1', reason: name);
      }
      expect(
        channelIdentity('CCTV-5 体育'),
        isNot(channelIdentity('CCTV-5+ 体育赛事')),
      );
      expect(channelIdentity('CCTV4欧洲'), isNot(channelIdentity('CCTV4美洲')));
      expect(channelIdentity('CCTV-16 4K'), isNot(channelIdentity('CCTV-16')));
      expect(channelIdentity('CCTV-1 测试'), isNot(channelIdentity('CCTV-1')));
    },
  );
  _repositoryTests();
}

late AppDatabase db;
late MediaHttpClient http;
late LiveRepository live;
late LiveHealthRepository health;

void _repositoryTests() {
  setUp(() {
    db = AppDatabase.memory();
    http = MediaHttpClient();
    live = LiveRepository(db, DocumentClient(http));
    health = LiveHealthRepository(db);
  });
  tearDown(() async {
    http.close();
    await db.close();
  });
  _crossSubscriptionTests();
  _sameListTests();
}

void _crossSubscriptionTests() {
  test(
    'cross-subscription aliases are one programme with scoped headers',
    () async {
      await live.importText(
        'one',
        Uri.parse('https://list.test/a'),
        'CCTV-1,https://one.test/a.ts',
        headers: {'Referer': 'https://one.test/'},
      );
      await live.importText(
        'two',
        Uri.parse('https://list.test/b'),
        'CCTV-1 综合,https://two.test/a.ts',
        headers: {'Referer': 'https://two.test/'},
      );
      final channel = (await live.channels()).single;
      expect(channel.name, 'CCTV-1 综合');
      expect(channel.urls, hasLength(2));
      expect(channel.preferenceIds, hasLength(2));
      expect(channel.headersFor(Uri.parse('https://one.test/a.ts')), {
        'Referer': 'https://one.test/',
      });
      expect(channel.headersFor(Uri.parse('https://two.test/a.ts')), {
        'Referer': 'https://two.test/',
      });
      expect(matchesChannel(channel, '央视', 'CCTV-1'), isTrue);
      await live.favorite(channel, true);
      expect((await live.channels()).single.favorite, isTrue);
      expect(
        await db.rows('SELECT * FROM channel_preferences WHERE favorite=1'),
        hasLength(2),
      );
    },
  );
  test(
    'deleting a source keeps other programme lines and survives renamed refresh',
    () async {
      final one = Uri.parse('https://list.test/a');
      await live.importText('one', one, 'CCTV-1,https://one.test/a.ts');
      await live.importText(
        'two',
        Uri.parse('https://list.test/b'),
        'CCTV-1 综合,https://two.test/a.ts',
      );
      final merged = (await live.channels()).single;
      await live.favorite(merged, true);
      final entry = merged.entries.firstWhere(
        (c) => c.urls.single.host == 'one.test',
      );
      await health.setRemoved([entry.id], true);
      await live.importText('one', one, 'CCTV1综合高清,https://one.test/new.ts');
      final channels = await live.channels();
      final visible = channels.where((c) => matchesChannel(c, '央视', '')).single;
      final removed = channels
          .where((c) => matchesChannel(c, '已移除', ''))
          .single;
      expect(visible.urls.single.host, 'two.test');
      expect(removed.id, entry.id);
      expect(removed.favorite, isTrue);
      expect(removed.urls.single.path, '/new.ts');
      final backup = BackupService(db);
      await backup.restore(await backup.preview(await backup.export()));
      expect(
        (await live.channels()).where((c) => c.health.removed),
        hasLength(1),
      );
      await health.setEnabled(removed.preferenceIds, true);
      expect((await live.channels()).single.urls, hasLength(2));
    },
  );
}

void _sameListTests() {
  test('same-list aliases combine without duplicating URLs', () async {
    await live.importText(
      'one',
      Uri.parse('https://list.test/a'),
      'CCTV-1,https://one.test/a.ts\nCCTV-1 综合,https://one.test/a.ts\nCCTV1综合高清,https://one.test/b.ts',
    );
    expect(await db.rows('SELECT * FROM live_channels'), hasLength(1));
    expect((await live.channels()).single.urls, hasLength(2));
  });
  test(
    'same tvg id with different headers retains each authentication scope',
    () async {
      await live.importText(
        'one',
        Uri.parse('https://list.test/a'),
        '#EXTM3U\n#EXTINF:-1 tvg-id="cctv1",CCTV1\n#EXTVLCOPT:http-referrer=https://one.test/\nhttps://one.test/a.ts\n'
            '#EXTINF:-1 tvg-id="cctv1",CCTV1 综合\n#EXTVLCOPT:http-referrer=https://two.test/\nhttps://two.test/b.ts',
      );
      final channel = (await live.channels()).single;
      expect(channel.entries, hasLength(2));
      expect(
        channel.headersFor(Uri.parse('https://one.test/a.ts'))['Referer'],
        'https://one.test/',
      );
      expect(
        channel.headersFor(Uri.parse('https://two.test/b.ts'))['Referer'],
        'https://two.test/',
      );
    },
  );
}
