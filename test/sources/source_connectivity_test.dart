import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/sources/application/source_connectivity.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test('only two matching NXDOMAIN answers confirm a missing domain', () async {
    var secondStatus = 0;
    var mismatch = false;
    final server = await HttpTestServer.start((request) {
      request.response.write(
        jsonEncode({
          'Status': request.uri.path == '/one' ? 3 : secondStatus,
          'Question': [
            {
              'name': mismatch ? 'other.example.net.' : 'gone.example.net.',
              'type': 1,
            },
          ],
        }),
      );
    });
    final http = MediaHttpClient(allowPrivateNetworks: true);
    addTearDown(() async {
      http.close();
      await server.close();
    });
    final connectivity = NetworkSourceConnectivity(
      DocumentClient(http),
      lookup: (_) async => [],
      resolvers: [
        server.baseUri.resolve('one').toString(),
        server.baseUri.resolve('two').toString(),
      ],
    );
    final uri = Uri.parse('https://gone.example.net/api');
    expect(
      (await connectivity.inspect(uri, CancellationToken())).missingDomain,
      isFalse,
    );
    secondStatus = 3;
    expect(
      (await connectivity.inspect(uri, CancellationToken())).missingDomain,
      isTrue,
    );
    mismatch = true;
    expect(
      (await connectivity.inspect(uri, CancellationToken())).missingDomain,
      isFalse,
    );
    final token = CancellationToken()..cancel();
    await expectLater(
      connectivity.inspect(uri, token),
      throwsA(isA<RequestCancelled>()),
    );
  });
}
