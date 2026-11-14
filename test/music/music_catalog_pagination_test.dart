import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/data/music_catalog_api.dart';
import 'package:zero_player/features/music/data/music_chart_catalog.dart';
import 'package:zero_player/features/music/data/music_recommendations.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/music_style_catalog.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import '../../test_support/http_test_server.dart';

void main() {
  _qqCategories();
  _neteasePagination();
  _chartRetry();
}

void _qqCategories() {
  test(
    'QQ official categories and playlist pages use the current site requests',
    () async {
      final (api, _) = await _fixture((request) {
        final req = _qqRequest(request);
        final params = req['param'] as Map;
        if (req['method'] == 'GetAllTag') {
          _qq(request, {
            'v_group': [
              {
                'group_name': '热门',
                'v_item': [
                  {'id': 3317, 'name': '官方歌单'},
                  {'id': 9527, 'name': 'AI歌单', 'source': 1},
                ],
              },
            ],
          });
        } else {
          expect(req['method'], 'get_category_content');
          expect(params['category_id'], 3317);
          final page = params['page'] as int;
          _qq(request, {
            'retcode': 0,
            'content': {
              'total_cnt': 21,
              'v_item': [
                {
                  'basic': {
                    'tid': page + 100,
                    'title': '歌单 $page',
                    'song_cnt': 72,
                  },
                },
              ],
            },
          });
        }
      });
      final catalog = _playlists(api);
      final token = CancellationToken();
      final options = await catalog.categories('qqPlaylist', token);
      final official = options.firstWhere((option) => option.id == '3317');
      final first = await catalog.playlists('qqPlaylist', official, token);
      expect(first.next, 1);
      expect(first.items.single.count, 72);
      final second = await catalog.playlists(
        'qqPlaylist',
        official,
        token,
        cursor: first.next!,
      );
      expect(second.items.single.id, '101');
      expect(second.next, isNull);
      final ai = options.firstWhere((option) => option.name == 'AI歌单');
      await expectLater(
        catalog.playlists('qqPlaylist', ai, token),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('登录'),
          ),
        ),
      );
    },
  );
}

void _neteasePagination() {
  test(
    'NetEase high-quality listing follows decreasing timestamp cursors',
    () async {
      final (api, _) = await _fixture((request) {
        expect(request.uri.path, '/api/playlist/highquality/list');
        final before = request.uri.queryParameters['lasttime'];
        _json(request, {
          'code': 200,
          'more': true,
          'lasttime': before == '0' ? 1000 : 900,
          'playlists': [
            {'id': before == '0' ? 1 : 2, 'name': '歌单'},
          ],
        });
      });
      final catalog = _playlists(api);
      final token = CancellationToken();
      final first = await catalog.playlists(
        'neteasePlaylist',
        neteaseHighQualityPlaylists,
        token,
      );
      expect(first.next, 1000);
      final second = await catalog.playlists(
        'neteasePlaylist',
        neteaseHighQualityPlaylists,
        token,
        cursor: first.next!,
      );
      expect(second.next, 900);
      expect(second.items.single.id, '2');
      final repeated = await catalog.playlists(
        'neteasePlaylist',
        neteaseHighQualityPlaylists,
        token,
        cursor: second.next!,
      );
      expect(repeated.next, isNull);
    },
  );
  test(
    'NetEase public playlist keeps order beyond 500 and requests only the selected batch',
    () async {
      final (api, server) = await _fixture((request) {
        if (request.uri.path == '/api/v6/playlist/detail') {
          _json(request, {
            'code': 200,
            'playlist': {
              'name': '公开歌单',
              'privacy': 0,
              'trackCount': 502,
              'trackIds': [
                for (var id = 1; id <= 502; id++) {'id': id},
              ],
              'tracks': [for (var id = 1; id <= 50; id++) _song(id)],
            },
          });
        } else {
          expect(request.uri.path, '/api/song/detail');
          final ids = (jsonDecode(request.uri.queryParameters['ids']!) as List)
              .cast<int>();
          expect(ids, [501, 502]);
          _json(request, {
            'code': 200,
            'songs': [_song(502), _song(800), _song(501)],
          });
        }
      });
      final token = CancellationToken();
      final read = await _playlists(
        api,
      ).open(const MusicStylePlaylist('neteasePlaylist', '123', '公开歌单'), token);
      final first = await read(0, token);
      expect(first.next, 50);
      expect(server.calls['/api/song/detail'], isNull);
      final last = await read(500, token);
      expect(last.total, 502);
      expect(last.next, isNull);
      expect(last.items.map((track) => track.id), ['501', '502']);
      expect(last.items.every((track) => track.searchOnly), isTrue);
      expect(server.calls['/api/v6/playlist/detail'], 1);
    },
  );
}

void _chartRetry() {
  test(
    'QQ chart keeps loaded rows after a failed next page and retries its offset',
    () async {
      var fail = true;
      final offsets = <int>[];
      final (api, _) = await _fixture((request) {
        final payload = jsonDecode(request.uri.queryParameters['data']!) as Map;
        if (payload.containsKey('req_0')) {
          _json(request, {
            'code': 0,
            'req_0': {
              'code': 0,
              'data': {
                'group': [
                  {
                    'groupName': '巅峰榜',
                    'toplist': [
                      {'topId': 26, 'title': '热歌榜'},
                    ],
                  },
                ],
              },
            },
            'req_1': {
              'code': 0,
              'data': {
                'data': {
                  'totalNum': 3,
                  'song': [
                    {'songId': 1, 'rank': 1},
                  ],
                },
                'songInfoList': [
                  {'id': 1, 'name': '歌曲'},
                ],
              },
            },
          });
          offsets.add(0);
          return;
        }
        final req = _qqRequest(request);
        if (req['method'] == 'GetAll') {
          _qq(request, {
            'group': [
              {
                'groupName': '巅峰榜',
                'toplist': [
                  {'topId': 26, 'title': '热歌榜'},
                ],
              },
            ],
          });
          return;
        }
        final offset = (req['param'] as Map)['offset'] as int;
        offsets.add(offset);
        if (offset > 0 && fail) {
          request.response.statusCode = 404;
          return;
        }
        _qq(request, {
          'data': {
            'totalNum': 3,
            'song': [
              {'songId': offset + 1, 'rank': offset + 1},
            ],
          },
          'songInfoList': [
            // Two distinct releases share a displayed title.
            {'id': offset + 1, 'name': '歌曲'},
          ],
        });
      });
      final db = AppDatabase.memory();
      final feed = MusicRecommendations(
        api.network,
        db,
        chartCatalog: MusicChartCatalog(api),
      );
      addTearDown(() async {
        await feed.close();
        await db.close();
      });
      await feed.selectChartPlatform('qqPlaylist');
      expect(feed.items.single.rank, 1);
      await feed.loadMore();
      expect(feed.items.single.id, '1');
      expect(feed.pageError, isNotNull);
      fail = false;
      await feed.loadMore();
      expect(feed.items.map((song) => song.rank), [1, 2]);
      expect(feed.pageError, isNull);
      await feed.loadMore();
      expect(feed.items.map((song) => song.id), ['1', '2', '3']);
      expect(feed.hasMore, isFalse);
      expect(offsets, [0, 1, 1, 2]);
    },
  );
}

MusicStyleCatalog _playlists(MusicCatalogApi api) =>
    MusicStyleCatalog(MusicRepository(MyFreeMp3Client(api.network)), api: api);

Map _song(int id) => {'id': id, 'name': '歌曲 $id'};

Map _qqRequest(HttpRequest request) =>
    (jsonDecode(request.uri.queryParameters['data']!) as Map)['req'] as Map;

void _qq(HttpRequest request, Map<String, Object?> data) => _json(request, {
  'code': 0,
  'req': {'code': 0, 'data': data},
});

void _json(HttpRequest request, Map<String, Object?> data) =>
    request.response.write(jsonEncode(data));

Future<(MusicCatalogApi, HttpTestServer)> _fixture(
  void Function(HttpRequest) reply,
) async {
  final server = await HttpTestServer.start(reply);
  final http = MediaHttpClient(allowPrivateNetworks: true);
  addTearDown(() async {
    http.close();
    await server.close();
  });
  return (
    MusicCatalogApi(
      DocumentClient(http),
      netease: server.baseUri,
      qq: server.baseUri,
      kugou: server.baseUri,
      kugouWeb: server.baseUri,
    ),
    server,
  );
}
