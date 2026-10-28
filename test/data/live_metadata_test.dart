import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/data/m3u_parser.dart';
import 'package:zero_player/features/live/domain/live_health.dart';
import 'package:zero_player/features/live/presentation/live_channel_filters.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import 'package:zero_player/media/hls/hls_manifest.dart';
import 'package:zero_player/media/hls/hls_probe_variant.dart';

void main() {
  test(
    'M3U metadata persists through aliases, export and backup; unknown stays unknown',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      addTearDown(() async {
        http.close();
        await db.close();
      });
      final live = LiveRepository(db, DocumentClient(http));
      final url = Uri.parse('https://list.test/list.m3u');
      const text =
          '#EXTM3U\n#EXTINF:-1 tvg-language="zho;eng" tvg-country="CN" tvg-resolution="1920x1080" group-title="新闻",CCTV1\nhttps://media.test/live.m3u8';
      await live.importText('TV', url, text);
      var c = (await live.channels()).single;
      expect(c.languages, ['zho', 'eng']);
      expect(c.categories, ['新闻']);
      expect(c.resolutions, ['1920x1080']);
      expect(
        const LiveChannelFilter(language: 'zho', category: '新闻').matches(c),
        isTrue,
      );
      expect(
        parseM3u(exportM3u([c]), url, 'other').single.languages,
        c.languages,
      );
      final backups = BackupService(db);
      final saved = await backups.preview(await backups.export());
      await backups.restore(saved);
      expect((await live.channels()).single.languages, c.languages);
      await live.importText(
        'TV',
        url,
        '#EXTM3U\n#EXTINF:-1,CCTV1\nhttps://media.test/new.m3u8',
      );
      c = (await live.channels()).single;
      expect(c.languages, isEmpty);
      expect(c.resolutions, isEmpty);
      expect(const LiveChannelFilter(language: '未知').matches(c), isTrue);
    },
  );
  test('selected video variant owns resolution and audio group metadata', () {
    final manifest = HlsManifest.parse(
      '#EXTM3U\n'
      '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="other",LANGUAGE="fra",URI="wrong.m3u8"\n'
      '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="main",LANGUAGE="zho",URI="audio.m3u8"\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720,AUDIO="main"\nvideo.m3u8\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1920x1080\nother.m3u8',
      Uri.parse('https://media.test/master.m3u8'),
    );
    final variant = probeVariant(manifest);
    expect(variant.uri.path, '/video.m3u8');
    expect(variant.resolution, '1280x720');
    expect(variant.languages, ['zho']);
  });
  _recoveryTest();
}

void _recoveryTest() {
  test(
    'recovery enables only responding entries and never resurrects removed ones',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      addTearDown(() async {
        http.close();
        await db.close();
      });
      final live = LiveRepository(db, DocumentClient(http));
      final health = LiveHealthRepository(db);
      await live.importText(
        'TV',
        Uri.parse('https://list.test/a'),
        'One,https://media.test/a',
      );
      final c = (await live.channels()).single;
      await health.record(
        c,
        const LiveHealth(availability: LiveAvailability.unavailable),
        disableUnavailable: true,
      );
      expect((await live.channels()).single.health.enabled, isFalse);
      await health.record(
        c,
        const LiveHealth(availability: LiveAvailability.inconclusive),
        enableResponding: true,
      );
      expect((await live.channels()).single.health.enabled, isFalse);
      await health.record(
        c,
        const LiveHealth(availability: LiveAvailability.responding),
        enableResponding: true,
      );
      expect((await live.channels()).single.health.enabled, isTrue);
      await health.setRemoved([c.id], true);
      await health.record(
        c,
        const LiveHealth(availability: LiveAvailability.responding),
        enableResponding: true,
      );
      expect((await live.channels()).single.health.enabled, isFalse);
      expect((await live.channels()).single.health.removed, isTrue);
    },
  );
}
