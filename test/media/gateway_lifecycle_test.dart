import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/gateway/media_gateway.dart';

import '../../test_support/http_test_server.dart';

void main() {
  test(
    'concurrent gateway starts share one bind and preserve injected HTTP ownership',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gateway-lifecycle',
      );
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final gateway = MediaGateway(SegmentStore(directory), client: http);
      final server = await HttpTestServer.start(
        (request) => request.response.write('alive'),
      );
      addTearDown(() async {
        await gateway.close();
        http.close();
        await server.close();
        await directory.delete(recursive: true);
      });
      final first = gateway.start();
      final second = gateway.start();
      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      await Future.wait([gateway.close(), gateway.close()]);
      final payload = await http.open(server.baseUri, policy: HeaderPolicy({}));
      expect(await utf8.decoder.bind(payload.body).join(), 'alive');
      await expectLater(gateway.start(), throwsStateError);
    },
  );
  for (final externalAudio in [false, true]) {
    test(
      'master media ad filtering respects external audio=$externalAudio',
      () => _filterTest(externalAudio),
    );
  }
}

Future<void> _filterTest(bool externalAudio) async {
  final directory = await Directory.systemTemp.createTemp('gateway-filter');
  final gateway = MediaGateway(
    SegmentStore(directory),
    allowPrivateNetworks: true,
  );
  final client = HttpClient();
  final server = await HttpTestServer.start((request) {
    if (request.uri.path == '/master.m3u8') {
      request.response.write(
        '#EXTM3U\n'
        '${externalAudio ? '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="main",URI="audio.m3u8"\n' : ''}'
        '#EXT-X-STREAM-INF:BANDWIDTH=100${externalAudio ? ',AUDIO="audio"' : ''}\nmedia.m3u8\n',
      );
    } else {
      request.response.write(
        '#EXTM3U\n#EXTINF:2,\nbefore.ts\n'
        '#EXT-X-CUE-OUT:2\n#EXTINF:2,\nad.ts\n#EXT-X-CUE-IN\n'
        '#EXTINF:2,\nafter.ts\n#EXT-X-ENDLIST\n',
      );
    }
  });
  addTearDown(() async {
    client.close(force: true);
    await gateway.close();
    await server.close();
    await directory.delete(recursive: true);
  });
  await gateway.start();
  final session = gateway.createSession(HeaderPolicy({}))..filterAds = true;
  final master = session.register(server.baseUri.resolve('master.m3u8'));
  final text = await _read(client, master);
  final media = Uri.parse(
    text.split('\n').firstWhere((line) => line.startsWith('http')),
  );
  final processed = await _read(client, media);
  expect(processed.split('#EXTINF:').length - 1, externalAudio ? 3 : 2);
  expect(
    session.timeline.toOriginal(const Duration(seconds: 3)),
    Duration(seconds: externalAudio ? 3 : 5),
  );
}

Future<String> _read(HttpClient client, Uri uri) async {
  final response = await (await client.getUrl(uri)).close();
  expect(response.statusCode, 200);
  return utf8.decoder.bind(response).join();
}
