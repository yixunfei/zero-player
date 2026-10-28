import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/gateway/media_gateway.dart';
import '../../test_support/http_test_server.dart';

void main() {
  late Directory root;
  late MediaGateway gateway;
  late HttpClient client;
  late HttpTestServer upstream;
  late Uri target;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('gateway-security-');
    gateway = MediaGateway(SegmentStore(root), allowPrivateNetworks: true);
    await gateway.start();
    upstream = await HttpTestServer.start((request) {
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.write(
        '<html><script>location.href="https://evil.test"</script></html>',
      );
    });
    final session = gateway.createSession(HeaderPolicy({}))
      ..cacheEnabled = false;
    target = session.register(
      upstream.baseUri.resolve('fake.mp4'),
      streaming: true,
    );
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await gateway.close();
    await upstream.close();
    await root.delete(recursive: true);
  });
  test('only a live registered playlist grants reference capability', () {
    final session = gateway.createSession(HeaderPolicy({}));
    final playlist = session.register(upstream.baseUri.resolve('index.m3u8'));
    expect(gateway.isRegisteredPlaylist(playlist), isTrue);
    expect(gateway.isRegisteredPlaylist(target), isFalse);
    expect(gateway.isRegisteredPlaylist(playlist.replace(port: 1)), isFalse);
    expect(
      gateway.isRegisteredPlaylist(playlist.replace(query: 'x=1')),
      isFalse,
    );
    expect(
      gateway.isRegisteredPlaylist(Uri.parse('file:///index.m3u8')),
      isFalse,
    );
    session.close();
    expect(gateway.isRegisteredPlaylist(playlist), isFalse);
  });
  test('browser and forged host requests never reach the upstream', () async {
    for (final header in {
      'Origin': 'https://evil.test',
      'Sec-Fetch-Site': 'cross-site',
      'Host': 'evil.test',
    }.entries) {
      final request = await client.getUrl(target);
      request.headers.set(header.key, header.value);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.forbidden);
      await response.drain<void>();
    }
    expect(upstream.calls, isEmpty);
  });
  test(
    'a webpage disguised as video cannot pass through the gateway',
    () async {
      final response = await (await client.getUrl(target)).close();
      expect(response.statusCode, HttpStatus.badGateway);
      final body = await utf8.decoder.bind(response).join();
      expect(body, 'Media request failed');
      expect(gateway.failures, 1);
    },
  );
}
