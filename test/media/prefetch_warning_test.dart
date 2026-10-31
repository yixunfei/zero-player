import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/media/cache/segment_fetcher.dart';
import 'package:zero_player/media/cache/segment_prefetcher.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/hls/hls_manifest.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'prefetch backs off and reports repeated failure once without throwing',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'zero-prefetch-warning-',
      );
      final server = await HttpTestServer.start(
        (r) => r.response.statusCode = 404,
      );
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final prefetch = SegmentPrefetcher(
        SegmentFetcher(SegmentStore(directory), http),
        HeaderPolicy({}),
      );
      addTearDown(() async {
        prefetch.close();
        http.close();
        await server.close();
        await directory.delete(recursive: true);
      });
      final warning = Completer<void>();
      var warnings = 0;
      prefetch.onUnavailable = () {
        warnings++;
        warning.complete();
      };
      prefetch.setManifest(
        HlsManifest.parse(
          '#EXTM3U\n#EXTINF:2,\nbad.ts\n#EXT-X-ENDLIST\n',
          server.baseUri.resolve('a.m3u8'),
        ),
      );
      prefetch.enabled = true;
      prefetch.playing = true;
      prefetch.kick();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.calls['/bad.ts'], 1);
      expect(warnings, 0);
      prefetch.kick();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.calls['/bad.ts'], 1);
      await Future<void>.delayed(const Duration(seconds: 10));
      prefetch.kick();
      await warning.future.timeout(const Duration(seconds: 3));
      expect(warnings, 1);
      prefetch.close();
      prefetch.kick();
      expect(server.calls['/bad.ts'], 2);
    },
  );
}
