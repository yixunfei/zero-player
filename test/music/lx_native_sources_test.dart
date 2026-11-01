import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/data/lx_native_sources.dart';
import 'package:zero_player/features/music/domain/music_track.dart';
import '../../test_support/http_test_server.dart';

MusicTrack _track(String provider) => MusicTrack(
  provider: provider,
  id: '1859245776',
  title: 'Song',
  artist: 'Artist',
  url: Uri.parse('https://example.com/song'),
  fetchedAt: DateTime.now(),
);

void main() {
  _postTests();
  _plantTests();
  test('native JSON POST retains private-target rejection', () async {
    final http = MediaHttpClient();
    final server = await HttpTestServer.start(
      (request) => fail('private request reached fixture'),
    );
    addTearDown(() async {
      http.close();
      await server.close();
    });
    await expectLater(
      DocumentClient(http).postJson(server.baseUri, {'source': 'wy'}),
      throwsFormatException,
    );
    expect(server.calls, isEmpty);
  });
}

void _postTests() {
  test(
    'native POST uses fixed JSON and rejects remote request instructions and redirects',
    () async {
      var redirect = false, instructions = false;
      final server = await HttpTestServer.start((request) async {
        expect(request.method, 'POST');
        expect(request.headers.contentType?.mimeType, 'application/json');
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        if (request.uri.path == '/music/url') {
          expect(body, {
            'source': 'wy',
            'musicId': '1859245776',
            'quality': '128k',
          });
        } else {
          expect((body['musicInfo'] as Map)['songmid'], '1859245776');
        }
        if (redirect) {
          request.response.statusCode = 307;
          request.response.headers.set('Location', '/should-never-be-called');
        } else {
          request.response.write(
            jsonEncode(
              instructions
                  ? {
                      'code': 303,
                      'data': {
                        'request': {'url': 'http://127.0.0.1/private'},
                      },
                    }
                  : {
                      'code': 200,
                      'data': {'url': 'https://example.com/audio.mp3'},
                    },
            ),
          );
        }
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final network = DocumentClient(http);
      final source = LxNativeSources(network, endpoint: server.baseUri);
      addTearDown(() async {
        http.close();
        await server.close();
      });
      expect(
        (await source.resolve(
          _track('lxHelloWorld'),
          CancellationToken(),
        )).url.path,
        '/audio.mp3',
      );
      instructions = true;
      await expectLater(
        source.resolve(_track('lxJuhe'), CancellationToken()),
        throwsFormatException,
      );
      instructions = false;
      redirect = true;
      await expectLater(
        source.resolve(_track('lxHelloWorld'), CancellationToken()),
        throwsA(isA<RemoteFailure>().having((e) => e.status, 'status', 307)),
      );
      expect(server.calls.containsKey('/should-never-be-called'), isFalse);
      final calls = server.calls.values.fold(0, (a, b) => a + b);
      await expectLater(
        network.postJson(server.baseUri, {'payload': 'x' * 65536}),
        throwsFormatException,
      );
      expect(server.calls.values.fold(0, (a, b) => a + b), calls);
    },
  );
}

void _plantTests() {
  test(
    'flower and grass preserve their distinct static tag protocols',
    () async {
      final tags = <String, String>{};
      final server = await HttpTestServer.start((request) {
        final tag = request.headers.value('tag')!;
        tags[request.uri.path] = utf8.decode([
          for (var i = 0; i < tag.length; i += 2)
            int.parse(tag.substring(i, i + 2), radix: 16),
        ]);
        request.response.write(
          jsonEncode({'code': 200, 'data': 'https://example.com/audio.mp3'}),
        );
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final source = LxNativeSources(
        DocumentClient(http),
        endpoint: server.baseUri,
      );
      addTearDown(() async {
        http.close();
        await server.close();
      });
      await source.resolve(_track('lxFlower'), CancellationToken());
      await source.resolve(_track('lxGrass'), CancellationToken());
      expect(
        tags['/flower/v1/url/wy/1859245776/128k'],
        '[\n "1859245776",\n "128k"\n]',
      );
      expect(tags['/grass/v1/url/kw/1859245776/128k'], '["1859245776","128k"]');
    },
  );
}
