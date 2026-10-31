import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/domain/epg_channel_match.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import '../../test_support/http_test_server.dart';

void main() {
  _displayNameGuideTest();
  test('guide aliases require unique evidence and respect declared IDs', () {
    expect(matchEpgChannel('', 'CCTV-1 综合', ['CCTV1']), 'CCTV1');
    expect(
      matchEpgChannel('', 'CCTV-5+ 体育赛事', ['CCTV5+', 'CCTV5+ 体育赛事']),
      isNull,
    );
    expect(matchEpgChannel('explicit', 'CCTV-1 综合', ['CCTV1']), isNull);
    expect(matchEpgChannel('', 'CCTV4美洲', ['CCTV4']), isNull);
    expect(matchEpgChannel('cctv1', '频道名', ['CCTV1']), 'CCTV1');
    expect(matchEpgChannel('cCtV1', '频道名', ['CCTV1', 'cctv1']), isNull);
  });
  test('publisher guide is stored and provides actual programme duration', () async {
    final now = DateTime.now().toUtc();
    String time(DateTime date) =>
        '${date.toIso8601String().replaceAll(RegExp('[-:T]'), '').substring(0, 14)} +0000';
    final start = now.subtract(const Duration(minutes: 10));
    final end = start.add(const Duration(minutes: 30));
    final server = await HttpTestServer.start((request) async {
      if (request.uri.path == '/bad') {
        request.response.statusCode = 503;
        return;
      }
      request.response.headers.contentType = ContentType(
        'application',
        'xml',
        charset: 'utf-8',
      );
      request.response.write(
        '<tv><programme channel="one" start="${time(start)}" stop="${time(end)}"><title>节目一</title></programme></tv>',
      );
    });
    final db = AppDatabase.memory();
    final http = MediaHttpClient(allowPrivateNetworks: true);
    addTearDown(() async {
      http.close();
      await server.close();
      await db.close();
    });
    final live = LiveRepository(db, DocumentClient(http));
    await live.importText(
      'TV',
      Uri.parse('https://list.test/a'),
      '#EXTM3U x-tvg-url="${server.baseUri}epg.xml"\n#EXTINF:-1 tvg-id="one",频道一\nhttps://media.test/a.ts',
    );
    final channel = (await live.channels()).single;
    expect((await live.lists()).single['epg_url'], '${server.baseUri}epg.xml');
    await live.importText(
      'Bad guide',
      Uri.parse('https://list.test/b'),
      '#EXTM3U x-tvg-url="${server.baseUri}bad"\n#EXTINF:-1 tvg-id="one",频道一\nhttps://media.test/b.ts',
    );
    await live.refreshSchedule((await live.channels()).single);
    await live.refreshSchedule(channel);
    final programme = (await live.schedule(channel)).single;
    expect(programme.title, '节目一');
    expect(programme.duration.inMinutes, 30);
  });
}

void _displayNameGuideTest() {
  test(
    'opaque XMLTV IDs match unique display names and removed guide stays removed',
    () async {
      final now = DateTime.now().toUtc();
      String time(DateTime date) =>
          '${date.toIso8601String().replaceAll(RegExp('[-:T]'), '').substring(0, 14)} +0000';
      final server = await HttpTestServer.start(
        (request) => request.response.write(
          '<tv><channel id="opaque"><display-name>CCTV-1 综合</display-name></channel>'
          '<programme channel="opaque" start="${time(now.subtract(const Duration(minutes: 10)))}" stop="${time(now.add(const Duration(minutes: 20)))}"><title>当前节目</title></programme></tv>',
        ),
      );
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      addTearDown(() async {
        http.close();
        await server.close();
        await db.close();
      });
      final live = LiveRepository(db, DocumentClient(http));
      const text =
          '#EXTM3U x-tvg-url="https://publisher.test/epg.xml"\n#EXTINF:-1,CCTV1\nhttps://media.test/live.ts';
      final url = Uri.parse('https://list.test/a');
      await live.importText('TV', url, text, epg: server.baseUri);
      await live.refreshEpg(server.baseUri);
      final channel = (await live.channels()).single;
      expect((await live.schedule(channel)).single.title, '当前节目');
      expect((await live.schedule(channel)).single.matchedByName, isTrue);
      await live.setGuide(channel.listId, null);
      await live.importText('TV', url, text);
      expect((await live.lists()).single['epg_url'], '');
      expect(await live.schedule(channel), isEmpty);
      final backup = BackupService(db);
      final saved = await backup.preview(await backup.export());
      await live.setGuide(channel.listId, server.baseUri);
      await backup.restore(saved);
      expect((await live.lists()).single['epg_url'], '');
    },
  );
}
