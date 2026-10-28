import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/request_trace.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'trace records real redirects and hides authorization, cookies and URL tokens',
    () async {
      final server = await HttpTestServer.start((request) {
        if (request.uri.path == '/start') {
          request.response.statusCode = 302;
          request.response.headers.set(
            'location',
            '/result?token=private-query',
          );
        } else {
          request.response.write('ok');
        }
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      addTearDown(() async {
        http.close();
        await server.close();
      });
      final entries = <Map<String, Object?>>[];
      await traceRequests(
        entries,
        () => DocumentClient(http).get(
          server.baseUri.resolve('start?api_key=private-key'),
          headers: {
            'Authorization': 'Bearer private-auth',
            'Cookie': 'private-cookie',
            'User-Agent': 'TestAgent',
          },
        ),
      );
      expect(entries.map((e) => e['status']), [302, 200]);
      final text = jsonEncode(entries);
      for (final secret in [
        'private-query',
        'private-key',
        'private-auth',
        'private-cookie',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(
        (entries.first['requestHeaders'] as Map)['user-agent'],
        'TestAgent',
      );
      expect(text, contains('已隐藏'));
    },
  );
}
