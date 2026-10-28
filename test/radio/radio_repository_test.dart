import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/radio/data/radio_repository.dart';
import '../../test_support/http_test_server.dart';
import 'package:zero_player/features/live/data/m3u_parser.dart';

void main() {
  test('malformed entries do not discard otherwise valid stations', () {
    final stations = parseM3u(
      '#EXTM3U\n#EXTINF:-1,坏地址\nhttp://[broken\n'
          '#EXTINF:-1 tvg-logo="http://[broken",<em>正常</em>电台\nhttps://example.com/a.mp3\n',
      Uri.parse('https://example.com/list.m3u'),
      'radio',
    );
    expect(stations, hasLength(1));
    expect(stations.single.name, '正常电台');
    expect(stations.single.logo, isEmpty);
  });
  test(
    'radio caches independently, preserves old list after a failed refresh',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      var requests = 0;
      var broken = false;
      final server = await HttpTestServer.start((request) async {
        requests++;
        if (broken) {
          request.response.statusCode = HttpStatus.notFound;
          return;
        }
        request.response.write(
          '#EXTM3U\n#EXTINF:-1 group-title="<b>音乐</b>",<em>中国</em>之声\nstream.mp3\n',
        );
      });
      addTearDown(() async {
        http.close();
        await server.close();
        await db.close();
      });
      final repo = RadioRepository(
        db,
        DocumentClient(http),
        source: server.baseUri.resolve('radio.m3u'),
      );
      final first = await repo.load();
      expect(first.stations.single.name, '中国之声');
      expect(first.stations.single.group, '音乐');
      expect(
        first.stations.single.urls.single,
        server.baseUri.resolve('stream.mp3'),
      );
      await repo.load();
      expect(requests, 1);
      expect(await db.rows('SELECT * FROM live_lists'), isEmpty);
      broken = true;
      final old = await repo.load(refresh: true);
      expect(old.stations.single.id, first.stations.single.id);
      expect(old.notice, isNotNull);
      final cancelled = CancellationToken()..cancel();
      await expectLater(
        repo.load(cancellation: cancelled),
        throwsA(isA<RequestCancelled>()),
      );
    },
  );

  test(
    'a corrupt radio snapshot is replaced with a valid network response',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final server = await HttpTestServer.start((request) async {
        request.response.write(
          '#EXTM3U\n#EXTINF:-1,电台\nhttps://example.com/live.mp3\n',
        );
      });
      addTearDown(() async {
        http.close();
        await server.close();
        await db.close();
      });
      final repo = RadioRepository(
        db,
        DocumentClient(http),
        source: server.baseUri,
      );
      await db.write('INSERT INTO app_meta VALUES(?,?)', [
        'radio_snapshot:${server.baseUri}',
        '{bad',
      ]);
      expect((await repo.load()).stations.single.name, '电台');
    },
  );
}
