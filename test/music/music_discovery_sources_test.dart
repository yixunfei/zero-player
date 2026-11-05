import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/data/music_discovery_sources.dart';
import 'package:zero_player/features/music/data/music_recommendations.dart';
import '../../test_support/http_test_server.dart';

Map<String, Object?> qq(String name) => {
  'code': 0,
  'req': {
    'code': 0,
    'data': {
      'songInfoList': [
        {
          'name': name,
          'singer': [
            {'name': '歌手'},
          ],
          'album': {'mid': 'ABC123', 'name': '专辑'},
        },
      ],
    },
  },
};
Map<String, Object?> apple(String name) => {
  'feed': {
    'results': [
      {
        'name': name,
        'artistName': '歌手',
        'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/100x100bb.jpg',
      },
    ],
  },
};

void main() {
  test('public provider shapes yield safe metadata and small covers', () {
    expect(parseQqHomepage(qq('<b>歌曲</b>')).single.query, '歌曲 歌手');
    expect(
      parseQqHomepage(qq('歌曲')).single.cover,
      contains('T002R300x300M000ABC123'),
    );
    expect(
      parseAppleHomepage(apple('歌曲')).single.cover,
      endsWith('300x300bb.jpg'),
    );
    expect(
      musicThumbnail('http://p1.music.126.net/a.jpg?x=1'),
      'https://p1.music.126.net/a.jpg?x=1&param=300y300',
    );
    expect(
      musicThumbnail('https://example.com/100x100bb.jpg'),
      endsWith('100x100bb.jpg'),
    );
    expect(musicThumbnail('file:///C:/secret'), isEmpty);
    expect(() => parseQqHomepage({'code': 0}), throwsFormatException);
    expect(() => parseAppleHomepage({'feed': {}}), throwsFormatException);
  });
  test(
    'default QQ homepage and chosen homepage survive restart with isolated caches',
    () async {
      final f = await _Fixture.open((request) {
        request.response.write(
          jsonEncode(
            request.uri.path == '/qq' ? qq('QQ 歌曲') : apple('Apple 歌曲'),
          ),
        );
      });
      addTearDown(f.close);
      var feed = f.create();
      await feed.initialize();
      expect(feed.chart, 'qqHome');
      expect(feed.items.single.title, 'QQ 歌曲');
      await feed.load('appleHome');
      await feed.close();
      final calls = f.server.calls.values.fold(0, (a, b) => a + b);
      feed = f.create();
      await feed.initialize();
      expect(feed.chart, 'appleHome');
      expect(feed.items.single.title, 'Apple 歌曲');
      expect(f.server.calls.values.fold(0, (a, b) => a + b), calls);
      await feed.load('qqHome');
      expect(feed.items.single.title, 'QQ 歌曲');
      await feed.close();
    },
  );
  _lifecycleTests();
}

void _lifecycleTests() {
  test(
    'stale cache displays before update and cancelled replies cannot replace the new source',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final f = await _Fixture.open((request) async {
        if (request.uri.path == '/qq') {
          entered.complete();
          await release.future;
        }
        request.response.write(
          jsonEncode(request.uri.path == '/qq' ? qq('迟到歌曲') : apple('新来源')),
        );
      });
      addTearDown(f.close);
      await f.db.write('INSERT INTO app_meta VALUES(?,?)', [
        'music_recommendation:qqHome',
        jsonEncode({
          'time': 0,
          'items': [
            {'title': '缓存歌曲', 'artist': '', 'cover': ''},
          ],
        }),
      ]);
      final feed = f.create();
      final old = feed.load('qqHome');
      await entered.future;
      expect(feed.items.single.title, '缓存歌曲');
      expect(feed.loading, isTrue);
      await feed.load('appleHome');
      release.complete();
      await old;
      expect(feed.items.single.title, '新来源');
      expect(feed.chart, 'appleHome');
      expect(feed.loading, isFalse);
      await feed.close();
    },
  );
  test(
    'cold slow source has browseable fallback and a hard deadline',
    () async {
      final release = Completer<void>();
      final f = await _Fixture.open((request) async {
        await release.future;
        request.response.write(jsonEncode(qq('迟到歌曲')));
      });
      addTearDown(f.close);
      final feed = f.create(timeout: const Duration(milliseconds: 80));
      final watch = Stopwatch()..start();
      await feed.load('qqHome');
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(feed.items, isNotEmpty);
      expect(feed.showingFallback, isTrue);
      expect(feed.loading, isFalse);
      expect(feed.notice, contains('编辑精选'));
      await feed.load('qqHome', refresh: true);
      expect(feed.showingFallback, isTrue);
      expect(feed.notice, contains('编辑精选'));
      release.complete();
      await feed.close();
    },
  );
  test('a user choice wins over pending homepage restoration', () async {
    final f = await _Fixture.open((request) {
      request.response.write(jsonEncode(apple('新选择')));
    });
    addTearDown(f.close);
    await f.db.write('INSERT INTO app_meta VALUES(?,?)', [
      'music_discovery_homepage',
      'home',
    ]);
    final feed = f.create();
    final restore = feed.initialize();
    await feed.load('appleHome');
    await restore;
    expect(feed.chart, 'appleHome');
    expect(feed.items.single.title, '新选择');
    await feed.close();
  });
}

final class _Fixture {
  _Fixture(this.server);
  final HttpTestServer server;
  final db = AppDatabase.memory();
  final http = MediaHttpClient(allowPrivateNetworks: true);
  static Future<_Fixture> open(
    FutureOr<void> Function(HttpRequest) handler,
  ) async => _Fixture(await HttpTestServer.start(handler));
  MusicRecommendations create({
    Duration timeout = const Duration(seconds: 6),
  }) => MusicRecommendations(
    DocumentClient(http),
    db,
    requestTimeout: timeout,
    homeEndpoints: {
      'qqHome': server.baseUri.resolve('/qq'),
      'appleHome': server.baseUri.resolve('/apple'),
    },
  );
  Future<void> close() async {
    http.close();
    await server.close();
    await db.close();
  }
}
