import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'redirects cannot forward credentials, cookies, device headers or referer',
    () async {
      final received = <Map<String, String>>[];
      final target = await HttpTestServer.start((request) {
        final headers = <String, String>{};
        request.headers.forEach(
          (name, values) => headers[name] = values.join(','),
        );
        received.add(headers);
        request.response.write('ok');
      });
      late HttpTestServer source;
      source = await HttpTestServer.start((request) {
        if (request.uri.path == '/start') {
          request.response.statusCode = 302;
          request.response.headers.set('location', '/next');
          request.response.cookies.add(Cookie('tracking', 'remote-id'));
        } else {
          expect(request.headers.value('authorization'), 'Bearer secret');
          expect(request.headers.value('cookie'), 'session=private');
          request.response.statusCode = 302;
          request.response.headers.set('location', target.baseUri.toString());
        }
      });
      final client = MediaHttpClient(allowPrivateNetworks: true);
      addTearDown(client.close);
      addTearDown(source.close);
      addTearDown(target.close);
      final payload = await client.open(
        source.baseUri.resolve('start'),
        policy: HeaderPolicy({
          source.baseUri: {
            'Authorization': 'Bearer secret',
            'Cookie': 'session=private',
            'X-Device-Id': 'unique',
            'Referer': 'https://origin.test/private',
          },
        }),
      );
      await payload.body.drain<void>();
      expect(received, hasLength(1));
      for (final name in [
        'authorization',
        'cookie',
        'x-device-id',
        'referer',
      ]) {
        expect(received.single[name], isNull, reason: name);
      }
    },
  );
}
