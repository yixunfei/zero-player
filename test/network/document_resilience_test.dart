import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/request_scheduler.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test('retry transient GET once and respect long Retry-After', () async {
    var calls = 0;
    final server = await HttpTestServer.start((request) async {
      calls++;
      if (request.uri.path == '/limited') {
        request.response.statusCode = 429;
        request.response.headers.set('retry-after', '60');
      } else if (calls == 1) {
        request.response.statusCode = 503;
        request.response.headers.set('retry-after', '0');
      } else {
        request.response.write('ok');
      }
    });
    final http = MediaHttpClient(allowPrivateNetworks: true);
    try {
      final client = DocumentClient(http);
      expect((await client.get(server.baseUri)).text, 'ok');
      expect(calls, 2);
      await expectLater(
        client.get(server.baseUri.resolve('limited')),
        throwsA(isA<RemoteFailure>()),
      );
      expect(calls, 3);
    } finally {
      http.close();
      await server.close();
    }
  });
  test('cancelling during backoff stops retries', () async {
    final responseSent = Completer<void>();
    var calls = 0;
    final server = await HttpTestServer.start((request) async {
      calls++;
      request.response.statusCode = 503;
      request.response.headers.set('retry-after', '2');
      if (!responseSent.isCompleted) responseSent.complete();
    });
    final http = MediaHttpClient(allowPrivateNetworks: true);
    final token = CancellationToken();
    try {
      final pending = DocumentClient(
        http,
      ).get(server.baseUri, cancellation: token);
      final checked = expectLater(
        pending,
        throwsA(
          isA<RemoteFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.cancelled,
          ),
        ),
      );
      await responseSent.future;
      token.cancel();
      await checked;
      expect(calls, 1);
    } finally {
      http.close();
      await server.close();
    }
  });
  test('playback reserve remains available under interactive load', () async {
    final scheduler = RequestScheduler(globalLimit: 3, playbackReserve: 1);
    final first = await scheduler.acquire(Uri.parse('https://a.test'));
    final second = await scheduler.acquire(Uri.parse('https://b.test'));
    var granted = false;
    final queued = scheduler.acquire(Uri.parse('https://c.test')).then((p) {
      granted = true;
      return p;
    });
    final playback = await scheduler.acquire(
      Uri.parse('https://d.test'),
      priority: RequestPriority.playback,
    );
    expect(granted, isFalse);
    first.release();
    second.release();
    playback.release();
    (await queued).release();
    scheduler.close();
  });
}
