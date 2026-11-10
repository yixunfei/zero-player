import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/data/kugou_music_source.dart';
import 'package:zero_player/features/music/data/netease_music_details.dart';
import 'package:zero_player/features/music/domain/music_lyrics.dart';
import 'package:zero_player/features/music/domain/music_track.dart';

import '../../test_support/http_test_server.dart';

void main() {
  test(
    'LRC handles repeated tags, offsets, blanks and filtered translations',
    () {
      final lyrics = MusicLyrics.parse(
        '[offset:-100]\r\n[00:01.2][00:03.040]第一行\n[00:02.00]\n'
            '[00:05]字面 [00:59] 标记',
        '[00:01.300]过滤词\n[00:03.140]翻译',
      ).filtered((text) => text != '过滤词');
      expect(lyrics.indexAt(const Duration(seconds: 1)), -1);
      expect(lyrics.indexAt(const Duration(milliseconds: 1300)), 0);
      expect(lyrics.indexAt(const Duration(seconds: 3)), 1);
      expect(lyrics.lines[1].text, isEmpty);
      expect(lyrics.lines[2].translation, '翻译');
      expect(lyrics.lines.last.text, '字面 [00:59] 标记');
      expect(lyrics.translatedLrc, '[00:03.140]翻译');
    },
  );
  _kugouTest();
  _playlistTest();
}

void _kugouTest() {
  test(
    'Kugou pages search and re-resolves only same-track HTTPS audio',
    () async {
      const id = '8267B85E29D936AE8FFBA797F64D5B0A';
      var audio = 'https://sharefs.kugou.com/audio.mp3';
      final server = await HttpTestServer.start((request) {
        if (request.uri.path == '/search') {
          expect(request.uri.queryParameters['page'], '2');
          expect(request.uri.queryParameters['keyword'], '理想三旬');
          request.response.write(
            jsonEncode({
              'status': 1,
              'data': {
                'total': 90,
                'lists': [
                  {
                    'FileHash': id,
                    'SongName': '<em>理想三旬</em>',
                    'Duration': 210,
                  },
                  {'FileHash': 'invalid', 'SongName': 'bad'},
                ],
              },
            }),
          );
        } else {
          expect(request.uri.queryParameters, {'cmd': 'playInfo', 'hash': id});
          request.response.write(
            jsonEncode({'status': 1, 'hash': id, 'url': audio}),
          );
        }
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      addTearDown(() async {
        http.close();
        await server.close();
      });
      final source = KugouMusicSource(
        DocumentClient(http),
        searchEndpoint: server.baseUri.resolve('/search'),
        audioEndpoint: server.baseUri.resolve('/audio'),
      );
      final token = CancellationToken();
      final result = await source.search('理想三旬', 2, token);
      expect(result.hasNext, isTrue);
      final track = MusicTrack.fromJson(result.tracks.single.toJson());
      expect(track.title, '理想三旬');
      expect(track.canDownload, isFalse);
      expect((await source.resolve(track, token)).url.toString(), audio);
      for (final denied in ['https://sharefs.kugou.com.evil.test/a.mp3', '']) {
        audio = denied;
        await expectLater(source.resolve(track, token), throwsFormatException);
      }
    },
  );
}

void _playlistTest() {
  test(
    'playlist links extract IDs and never request arbitrary hosts',
    () async {
      var requests = 0;
      var privacy = 0;
      final server = await HttpTestServer.start((request) {
        requests++;
        if (request.uri.path == '/api/song/detail') {
          expect(jsonDecode(request.uri.queryParameters['ids']!), [20, 30]);
          request.response.write(
            jsonEncode({
              'code': 200,
              'songs': [
                {'id': 30, 'name': '第三首'},
                {'id': 20, 'name': '第一首'},
                {'id': 40, 'name': '不在歌单'},
              ],
            }),
          );
          return;
        }
        expect(request.uri.path, '/api/v6/playlist/detail');
        expect(request.uri.queryParameters['id'], '3778678');
        request.response.write(
          jsonEncode({
            'code': 200,
            'playlist': {
              'privacy': privacy,
              'name': '公开歌单',
              'trackCount': 3,
              'trackIds': [
                {'id': 20},
                {'id': 287935},
                {'id': 30},
              ],
              'tracks': [
                {
                  'id': 287935,
                  'name': '一切为明天',
                  'dt': 180000,
                  'ar': [
                    {'name': '苏芮'},
                  ],
                },
                {'id': [], 'name': '无效曲目'},
              ],
            },
          }),
        );
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      addTearDown(() async {
        http.close();
        await server.close();
      });
      final details = NeteaseMusicDetails(
        DocumentClient(http),
        endpoint: server.baseUri,
      );
      final token = CancellationToken();
      await expectLater(
        details.playlist(
          'https://music.163.com.evil.test/playlist?id=3778678',
          token,
        ),
        throwsFormatException,
      );
      expect(requests, 0);
      final result = await details.playlist(
        'https://music.163.com/#/playlist?id=3778678',
        token,
      );
      expect(result.total, 3);
      expect(result.tracks.map((track) => track.id), ['20', '287935', '30']);
      expect(result.tracks[1].artist, '苏芮');
      expect(result.tracks[1].duration.inMinutes, 3);
      privacy = 10;
      await expectLater(
        details.playlist('3778678', token),
        throwsFormatException,
      );
    },
  );
}
