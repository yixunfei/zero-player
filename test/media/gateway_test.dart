import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/gateway/media_gateway.dart';

import '../../test_support/http_test_server.dart';

void main() {
  gatewayTests();
  transportTests();
}

void gatewayTests() {
  late Directory directory;
  late MediaGateway gateway;
  late HttpClient client;
  late HttpTestServer upstream;
  late GatewaySession session;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zero-gateway-test-');
    gateway = MediaGateway(SegmentStore(directory), allowPrivateNetworks: true);
    await gateway.start();
    client = HttpClient();
    upstream = await HttpTestServer.start(handleFixture);
    session = gateway.createSession(
      HeaderPolicy({
        upstream.baseUri: {'X-Fixture': 'allowed'},
      }),
    );
  });
  tearDown(() async {
    client.close(force: true);
    await gateway.close();
    await upstream.close();
    await directory.delete(recursive: true);
  });

  test(
    'opaque loopback URLs; rejects unknown token and revoked sessions',
    () async {
      expect(gateway.baseUri.host, '127.0.0.1');
      final target = session.register(upstream.baseUri.resolve('part.ts'));
      expect(target.query, isEmpty);
      expect(target.toString(), isNot(contains('part.ts')));
      session.close();
      final response = await (await client.getUrl(target)).close();
      expect(response.statusCode, 404);
      await response.drain<void>();
    },
  );

  test(
    'manifest redirect base, key/map rewriting and no manifest caching',
    () async {
      final target = session.register(
        upstream.baseUri.resolve('redirect.m3u8'),
      );
      for (var i = 0; i < 2; i++) {
        final response = await (await client.getUrl(target)).close();
        expect(response.statusCode, 200);
        final body = await utf8.decoder.bind(response).join();
        expect(body, contains('#EXT-X-DISCONTINUITY'));
        expect(body, isNot(contains('key.bin')));
        final segment = body
            .split('\n')
            .firstWhere((line) => line.startsWith('http'));
        final data = await (await client.getUrl(Uri.parse(segment))).close();
        expect(await data.expand((chunk) => chunk).toList(), [1, 2, 3, 4]);
      }
      expect(upstream.calls['/folder/index.m3u8'], 2);
      expect(upstream.calls['/folder/part.ts'], 1);
    },
  );

  test(
    'range responses retain status, content range and cache identity',
    () async {
      final target = session.register(upstream.baseUri.resolve('part.ts'));
      for (final range in ['bytes=0-1', 'bytes=2-3', 'bytes=0-1']) {
        final request = await client.getUrl(target);
        request.headers.set('Range', range);
        final response = await request.close();
        expect(response.statusCode, 206);
        expect(
          response.headers.value('content-range'),
          '${range.replaceFirst('=', ' ')}/4',
        );
        expect(
          await response.expand((chunk) => chunk).toList(),
          range == 'bytes=0-1' ? [1, 2] : [3, 4],
        );
      }
      expect(upstream.calls['/part.ts'], 2);
    },
  );
}

Future<void> handleFixture(HttpRequest request) async {
  if (request.headers.value('X-Fixture') != 'allowed') {
    request.response.statusCode = 403;
    return;
  }
  if (request.uri.path == '/redirect.m3u8') {
    request.response.statusCode = 302;
    request.response.headers.set('Location', '/folder/index.m3u8');
  } else if (request.uri.path.endsWith('.m3u8')) {
    request.response.write(
      '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
      '#EXT-X-MAP:URI="init.mp4"\n#EXT-X-DISCONTINUITY\n#EXTINF:2,\npart.ts\n#EXT-X-ENDLIST\n',
    );
  } else {
    final range = request.headers.value('Range');
    if (range == null) {
      request.response.add([1, 2, 3, 4]);
    } else {
      request.response.statusCode = 206;
      request.response.headers.set(
        'Content-Range',
        '${range.replaceFirst('=', ' ')}/4',
      );
      request.response.add(range == 'bytes=0-1' ? [1, 2] : [3, 4]);
    }
  }
}

void transportTests() {
  test(
    'cross-origin redirect never forwards credentials or custom headers',
    () async {
      Map<String, String?>? observed;
      final target = await HttpTestServer.start((request) {
        observed = {
          for (final name in ['authorization', 'cookie', 'referer', 'x-secret'])
            name: request.headers.value(name),
        };
        request.response.write('ok');
      });
      final source = await HttpTestServer.start((request) {
        request.response.statusCode = 302;
        request.response.headers.set('location', target.baseUri.toString());
      });
      final client = MediaHttpClient(allowPrivateNetworks: true);
      try {
        final payload = await client.open(
          source.baseUri,
          policy: HeaderPolicy({
            source.baseUri: {
              'Authorization': 'secret',
              'Cookie': 'secret',
              'Referer': 'secret',
              'X-Secret': 'secret',
            },
          }),
        );
        expect(await utf8.decoder.bind(payload.body).join(), 'ok');
        expect(observed!.values, everyElement(isNull));
      } finally {
        client.close();
        await source.close();
        await target.close();
      }
    },
  );

  test('cancelling pending response aborts the request promptly', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    final upstream = await HttpTestServer.start((request) async {
      received.complete();
      await release.future;
    });
    final client = MediaHttpClient(allowPrivateNetworks: true);
    final token = CancellationToken();
    try {
      final pending = client.open(
        upstream.baseUri,
        policy: HeaderPolicy({}),
        cancellation: token,
      );
      final expectation = expectLater(
        pending,
        throwsA(isA<RequestCancelled>()),
      );
      await received.future;
      token.cancel();
      await expectation.timeout(const Duration(seconds: 1));
    } finally {
      release.complete();
      client.close();
      await upstream.close();
    }
  });
}
