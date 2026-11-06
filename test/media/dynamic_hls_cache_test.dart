import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/gateway/media_gateway.dart';
import '../../test_support/http_test_server.dart';

void main() {
  for (final staticFirst in [false, true]) {
    test(
      'mutable HLS bytes are not replayed from an old cache (static first: $staticFirst)',
      () async {
        final root = await Directory.systemTemp.createTemp('mutable-hls-');
        var manifests = 0, segments = 0;
        final upstream = await HttpTestServer.start((request) {
          if (request.uri.path.endsWith('.m3u8')) {
            manifests++;
            request.response.write(
              '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:$manifests\n'
              '#EXTINF:2,\npart.ts\n${staticFirst && manifests == 1 ? '#EXT-X-ENDLIST\n' : ''}',
            );
          } else {
            request.response.headers.contentType = ContentType('video', 'mp2t');
            request.response.add([0x47, ++segments, 0, 0]);
          }
        });
        final gateway = MediaGateway(
          SegmentStore(root),
          allowPrivateNetworks: true,
        );
        await gateway.start();
        final client = HttpClient();
        try {
          final session = gateway.createSession(HeaderPolicy({}))
            ..normalizeTimestamps = staticFirst;
          final playlist = session.register(
            upstream.baseUri.resolve('index.m3u8'),
          );
          final received = <int>[];
          for (var i = 0; i < 2; i++) {
            final response = await (await client.getUrl(playlist)).close();
            final manifest = await utf8.decoder.bind(response).join();
            final uri = Uri.parse(
              manifest
                  .split('\n')
                  .firstWhere((line) => line.startsWith('http')),
            );
            final media = await (await client.getUrl(uri)).close();
            received.add((await media.expand((chunk) => chunk).toList())[1]);
          }
          expect(
            received,
            [1, 2],
            reason:
                'an upstream rolling/ad-inserted playlist can reuse resource paths',
          );
        } finally {
          client.close(force: true);
          await gateway.close();
          await upstream.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
