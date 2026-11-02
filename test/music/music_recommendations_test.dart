import 'dart:convert';
import 'package:zero_player/features/music/data/music_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/data/music_recommendations.dart';
import '../../test_support/http_test_server.dart';

Map<String, Object?> chart(String title) => {
  'code': 200,
  'result': {
    'tracks': [
      {
        'name': title,
        'artists': [
          {'name': '歌手'},
        ],
        'album': {'name': '专辑', 'picUrl': 'https://example.com/cover.jpg'},
      },
    ],
  },
};
void main() {
  test('malformed optional recommendation metadata does not discard songs', () {
    final home = parseHomepageSongs({
      'code': 200,
      'result': [
        {
          'name': 'Song',
          'song': {'artists': 'invalid', 'album': 1},
        },
      ],
    });
    expect(home.single.title, 'Song');
    expect(home.single.artist, '');
    final charts = parseMusicRecommendations({
      'code': 200,
      'playlist': {
        'tracks': [
          null,
          {
            'name': 'Song',
            'ar': [null],
            'al': 'invalid',
          },
        ],
      },
    });
    expect(charts.single.title, 'Song');
  });
  _homepageTest();
  test(
    'editorial playlists cover categories and work without network',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      final feed = MusicRecommendations(DocumentClient(http), db);
      addTearDown(() async {
        feed.close();
        http.close();
        await db.close();
      });
      for (final entry in musicCollections.entries) {
        await feed.load(entry.key);
        expect(feed.category, entry.value.category);
        expect(feed.items, isNotEmpty);
        expect(feed.items.every((song) => song.query.isNotEmpty), isTrue);
        expect(feed.loading, isFalse);
        expect(feed.notice, contains('编辑精选'));
      }
    },
  );
  test(
    'real chart shapes and WFU themes produce search metadata, not embedded stream URLs',
    () {
      final result = parseMusicRecommendations(chart('<b>晴天</b>'));
      expect(result.single.title, '晴天');
      expect(result.single.query, '晴天 歌手');
      expect(result.single.cover, 'https://example.com/cover.jpg');
      final wfu = parseWfuRecommendations(
        '<div class="channel-group"><li data-id="123456789ab"><a>周杰倫(直播)</a></li></div>',
      );
      expect(wfu.single.title, '周杰倫');
      expect(wfu.single.cover, contains('i.ytimg'));
      expect(
        () => parseMusicRecommendations({'code': 200, 'result': {}}),
        throwsFormatException,
      );
    },
  );
  test(
    'recommendations cache survives failed updates and does not refetch fresh entries',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      var fail = false;
      final server = await HttpTestServer.start((request) {
        if (fail) {
          request.response.statusCode = 404;
          return;
        }
        request.response.write(jsonEncode(chart('music')));
      });
      final feed = MusicRecommendations(
        DocumentClient(http),
        db,
        endpoint: server.baseUri,
      );
      addTearDown(() async {
        feed.close();
        http.close();
        await server.close();
        await db.close();
      });
      await feed.load('hot');
      expect(feed.items.single.title, 'music');
      await feed.load('hot');
      expect(server.calls.values.single, 1);
      fail = true;
      await feed.load('hot', refresh: true);
      expect(feed.items.single.title, 'music');
      expect(feed.notice, contains('缓存'));
      expect(feed.loading, isFalse);
      fail = false;
      await db.write('UPDATE app_meta SET value=? WHERE key=?', [
        'invalid cache',
        'music_recommendation:hot',
      ]);
      await feed.load('hot');
      expect(feed.items.single.title, 'music');
      expect(feed.notice, isNull);
    },
  );
}

void _homepageTest() {
  test('default discovery requests public homepage metadata', () async {
    final db = AppDatabase.memory();
    final http = MediaHttpClient(allowPrivateNetworks: true);
    final server = await HttpTestServer.start((request) {
      expect(request.uri.path, '/api/personalized/newsong');
      request.response.write(
        jsonEncode({
          'code': 200,
          'result': [
            {
              'name': '新歌',
              'picUrl': 'https://example.com/cover.jpg',
              'song': {
                'artists': [
                  {'name': '歌手'},
                ],
              },
            },
          ],
        }),
      );
    });
    final feed = MusicRecommendations(
      DocumentClient(http),
      db,
      endpoint: server.baseUri,
    );
    addTearDown(() async {
      feed.close();
      http.close();
      await server.close();
      await db.close();
    });
    expect(feed.chart, 'home');
    await feed.load(feed.chart);
    expect(feed.items.single.query, '新歌 歌手');
  });
  test('anonymous homepage songs provide search metadata only', () {
    final songs = parseHomepageSongs({
      'code': 200,
      'result': [
        {
          'name': '<b>新歌</b>',
          'picUrl': 'http://example.com/cover.jpg',
          'song': {
            'artists': [
              {'name': '歌手'},
            ],
            'album': {'name': '专辑'},
          },
        },
      ],
    });
    expect(songs.single.title, '新歌');
    expect(songs.single.query, '新歌 歌手');
    expect(songs.single.cover, 'https://example.com/cover.jpg');
    expect(() => parseHomepageSongs({'code': 200}), throwsFormatException);
  });
}
