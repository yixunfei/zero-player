import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/downloads/application/download_format.dart';

void main() {
  test('extensionless media is sniffed with a bounded range', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = MediaHttpClient(allowPrivateNetworks: true);
    server.listen((request) async {
      expect(request.headers.value('range'), 'bytes=0-511');
      request.response.add(
        request.uri.path == '/mp4'
            ? [0, 0, 0, 24, ...'ftypisom'.codeUnits]
            : '#EXTM3U\n#EXTINF:4,\na.ts\n'.codeUnits,
      );
      await request.response.close();
    });
    try {
      for (final name in ['mp4', 'hls']) {
        expect(
          await isMp4Download(
            Uri.parse('http://127.0.0.1:${server.port}/$name'),
            http,
            HeaderPolicy({}),
            CancellationToken(),
          ),
          name == 'mp4',
        );
      }
    } finally {
      http.close();
      await server.close(force: true);
    }
  });
}
