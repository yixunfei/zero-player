import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/data/flac_music_sources.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test('anonymous form search resolves a validated audition URL', () async {
    final http = MediaHttpClient(allowPrivateNetworks: true);
    var unsafe = false;
    var malformedFormats = false;
    final server = await HttpTestServer.start((request) async {
      expect(request.method, 'POST');
      expect(
        request.headers.contentType?.mimeType,
        'application/x-www-form-urlencoded',
      );
      final body = Uri.splitQueryString(
        await utf8.decoder.bind(request).join(),
      );
      expect(body['platform'], 'kuwo');
      if (request.uri.queryParameters['act'] == 'search') {
        expect(body['keyword'], 'song');
        request.response.write(
          jsonEncode({
            'code': 0,
            'data': {
              'total': 21,
              'list': [
                {
                  'id': '123',
                  'name': '<b>Song</b>',
                  'artist': 'Artist',
                  'duration': '60',
                  'time': 123456,
                  'sign': 'a' * 32,
                  'minfo': malformedFormats
                      ? 'invalid'
                      : [
                          {'format': 'mp3', 'bitrate': '128'},
                        ],
                },
              ],
            },
          }),
        );
      } else {
        expect(body['songid'], '123');
        expect(body['bitrate'], '128');
        request.response.write(
          jsonEncode({
            'code': 0,
            'data': {
              'url': unsafe
                  ? 'file:///secret'
                  : 'https://media.example/song.mp3',
            },
          }),
        );
      }
    });
    addTearDown(() async {
      http.close();
      await server.close();
    });
    final source = FlacMusicSources(
      DocumentClient(http),
      endpoint: server.baseUri,
    );
    final result = await source.search('song', 1, null);
    expect(result.tracks.single.title, 'Song');
    expect(result.tracks.single.downloadable, isFalse);
    expect(result.hasNext, isTrue);
    final resolved = await source.resolve(
      result.tracks.single,
      CancellationToken(),
    );
    expect(resolved.url.host, 'media.example');
    malformedFormats = true;
    await expectLater(
      source.resolve(result.tracks.single, CancellationToken()),
      throwsFormatException,
    );
    malformedFormats = false;
    unsafe = true;
    await expectLater(
      source.resolve(result.tracks.single, CancellationToken()),
      throwsFormatException,
    );
  });
}
