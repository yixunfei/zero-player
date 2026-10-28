import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/request_scheduler.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'rejected responses release permits before the next request',
    () async {
      final scheduler = RequestScheduler(globalLimit: 1);
      final http = MediaHttpClient(
        allowPrivateNetworks: true,
        scheduler: scheduler,
      );
      final server = await HttpTestServer.start((request) async {
        request.response.statusCode = 404;
        request.response.write('missing');
      });
      try {
        for (var i = 0; i < 3; i++) {
          await expectLater(
            DocumentClient(http).get(server.baseUri),
            throwsA(isA<RemoteFailure>()),
          );
        }
      } finally {
        http.close();
        scheduler.close();
        await server.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}
