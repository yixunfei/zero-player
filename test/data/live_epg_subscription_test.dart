import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/domain/epg_channel_match.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test('guide aliases require unique evidence and respect declared IDs', () {
    expect(matchEpgChannel('', 'CCTV-1 综合', ['CCTV1']), 'CCTV1');
    expect(
      matchEpgChannel('', 'CCTV-5+ 体育赛事', ['CCTV5+', 'CCTV5+ 体育赛事']),
      isNull,
    );
    expect(matchEpgChannel('explicit', 'CCTV-1 综合', ['CCTV1']), isNull);
    expect(matchEpgChannel('', 'CCTV4美洲', ['CCTV4']), isNull);
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
