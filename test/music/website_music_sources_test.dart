import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/data/website_music_sources.dart';
import '../../test_support/http_test_server.dart';

void main() {
  _qqTests();
  _boxTests();
}

void _qqTests() {
  test(
    'QQMP3 headers, pagination, nested URL and cover parsing use site protocol',
    () async {
      var unsafe = false;
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final server = await HttpTestServer.start((request) {
        expect(request.headers.value('referer'), 'https://www.qqmp3.vip/');
        expect(request.headers.value('x-requested-with'), 'XMLHttpRequest');
        request.response.write(
          jsonEncode(
            request.uri.path.endsWith('songs.php')
                ? {
                    'code': 200,
                    'data': [
                      for (var i = 0; i < 31; i++)
                        {
                          'rid': '$i',
                          'name': '<b>Song</b>',
                          'artist': 'Artist',
                          'pic': 'https://example.com/cover.jpg',
                        },
                    ],
                  }
                : {
                    'code': 200,
                    'data': {
                      'url': unsafe
                          ? 'file:///secret'
                          : 'https://media.example/song.mp3',
                    },
                  },
          ),
        );
      });
      addTearDown(() async {
        http.close();
        await server.close();
      });
      final client = WebsiteMusicSources(
        DocumentClient(http),
        qqEndpoint: server.baseUri,
      );
      final first = await client.search('qqmp3', 'song', 1, null);
      expect(first.tracks, hasLength(30));
      expect(first.hasNext, isTrue);
      expect(first.tracks.first.title, 'Song');
      expect(first.tracks.first.downloadable, isFalse);
      final last = await client.search('qqmp3', 'song', 2, null);
      expect(last.tracks, hasLength(1));
      expect(last.hasNext, isFalse);
      expect(
        (await client.resolve(
          first.tracks.first,
          CancellationToken(),
        )).url.host,
        'media.example',
      );
      unsafe = true;
      await expectLater(
        client.resolve(first.tracks.first, CancellationToken()),
        throwsFormatException,
      );
    },
  );
}

void _boxTests() {
  test(
    'musicBox uses its API origin and stable native meting identifiers',
    () async {
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final server = await HttpTestServer.start((request) {
        expect(request.headers.value('origin'), 'https://mu-jie.cc');
        expect(request.uri.queryParameters['pn'], '2');
        request.response.write(
          jsonEncode([
            {
              'id': '123',
              'name': 'music',
              'artist': 'artist',
              'url': 'file:///bad',
              'pic': '',
            },
          ]),
        );
      });
      addTearDown(() async {
        http.close();
        await server.close();
      });
      final client = WebsiteMusicSources(
        DocumentClient(http),
        boxEndpoint: server.baseUri,
      );
      final result = await client.search('musicBox', 'music', 2, null);
      final resolved = await client.resolve(
        result.tracks.single,
        CancellationToken(),
      );
      expect(resolved.url.path, '/meting/');
      expect(resolved.url.queryParameters['id'], '123');
      expect(
        resolved.url.scheme,
        'http',
        reason: 'only explicit loopback fixture permits HTTP',
      );
    },
  );
}
