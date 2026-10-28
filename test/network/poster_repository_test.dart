import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/poster_repository.dart';
import '../../test_support/http_test_server.dart';

final jpeg = [0xff, 0xd8, 0xff, ...List.filled(20, 0)];
void main() {
  _policyTests();
  _networkTests();
  _cancellationTests();
}

void _policyTests() {
  test('poster headers are limited to the public CDN origin', () {
    expect(
      posterHeaders(Uri.parse('https://img3.doubanio.com/a'))['Referer'],
      'https://movie.douban.com/',
    );
    expect(
      posterHeaders(
        Uri.parse('https://doubanio.com.evil.test/a'),
      ).containsKey('Referer'),
      isFalse,
    );
    expect(
      posterHeaders(Uri.parse('https://source.test/a')).containsKey('Cookie'),
      isFalse,
    );
    expect(isPosterPayload(utf8.encode('<script>challenge</script>')), isFalse);
    expect(isPosterPayload(jpeg), isTrue);
  });
}

void _networkTests() {
  test(
    'visible consumers share a request and releasing one does not abort another',
    () async {
      final started = Completer<void>();
      final complete = Completer<void>();
      final server = await HttpTestServer.start((request) async {
        started.complete();
        await complete.future;
        request.response.add(jpeg);
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final posters = PosterRepository(DocumentClient(http));
      final a = posters.acquire('${server.baseUri}poster');
      final b = posters.acquire('${server.baseUri}poster');
      final result = Future.wait([a.bytes, b.bytes]);
      await started.future;
      a.release();
      complete.complete();
      expect((await result).length, 2);
      b.release();
      final cached = posters.acquire('${server.baseUri}poster');
      await cached.bytes;
      cached.release();
      expect(server.calls['/poster'], 1);
      expect(posters.pendingCount, 0);
      posters.close();
      http.close();
      await server.close();
    },
  );
  test(
    'HTML success bodies are rejected and failures are briefly cached',
    () async {
      final server = await HttpTestServer.start((r) {
        r.response.write('<script>challenge</script>');
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final posters = PosterRepository(DocumentClient(http));
      for (var i = 0; i < 2; i++) {
        final lease = posters.acquire('${server.baseUri}bad');
        await expectLater(lease.bytes, throwsFormatException);
        lease.release();
      }
      expect(server.calls['/bad'], 1);
      posters.retry('${server.baseUri}bad');
      final lease = posters.acquire('${server.baseUri}bad');
      await expectLater(lease.bytes, throwsFormatException);
      lease.release();
      expect(server.calls['/bad'], 2);
      posters.close();
      http.close();
      await server.close();
    },
  );
  test('compressed image cache evicts by bytes and explicit cleanup', () async {
    final server = await HttpTestServer.start((r) {
      r.response.add(jpeg);
    });
    final http = MediaHttpClient(allowPrivateNetworks: true);
    final posters = PosterRepository(
      DocumentClient(http),
      maxBytes: jpeg.length * 2,
    );
    for (final path in ['a', 'b', 'c', 'a']) {
      final lease = posters.acquire('${server.baseUri}$path');
      await lease.bytes;
      lease.release();
    }
    expect(server.calls['/a'], 2);
    expect(posters.cachedBytes, lessThanOrEqualTo(jpeg.length * 2));
    posters.clear();
    expect(posters.cachedBytes, 0);
    posters.close();
    http.close();
    await server.close();
  });
}

void _cancellationTests() {
  test('last release cancels queued and active image work', () async {
    final started = Completer<void>();
    final finish = Completer<void>();
    final server = await HttpTestServer.start((r) async {
      started.complete();
      await finish.future;
      try {
        r.response.add(jpeg);
      } catch (_) {
        /* Cancelled client. */
      }
    });
    final http = MediaHttpClient(allowPrivateNetworks: true);
    final posters = PosterRepository(DocumentClient(http), concurrency: 1);
    final active = posters.acquire('${server.baseUri}active');
    final activeResult = expectLater(active.bytes, throwsA(anything));
    await started.future;
    final queued = posters.acquire('${server.baseUri}queued');
    final queuedResult = expectLater(queued.bytes, throwsA(anything));
    queued.release();
    active.release();
    await Future.wait([activeResult, queuedResult]);
    finish.complete();
    expect(posters.pendingCount, 0);
    expect(server.calls['/queued'], isNull);
    posters.close();
    http.close();
    await server.close();
  });
}
