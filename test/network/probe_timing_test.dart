import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/request_scheduler.dart';
import 'package:zero_player/media/network/media_probe.dart';
import '../../test_support/http_test_server.dart';

void main() {
  _mediaTests();
  _queueTests();
  _timeoutTests();
}

void _timeoutTests() {
  test('a stalled body expires and releases its scheduler permit', () async {
    final finish = Completer<void>();
    final server = await HttpTestServer.start((r) async {
      r.response.bufferOutput = false;
      r.response.write('x');
      await r.response.flush();
      if (r.uri.path == '/stall') await finish.future;
    });
    final scheduler = RequestScheduler(globalLimit: 1, originLimit: 1);
    final http = MediaHttpClient(scheduler: scheduler);
    try {
      await expectLater(
        probeMedia(
          http,
          server.baseUri.resolve('stall'),
          HeaderPolicy({}),
          CancellationToken(),
          availabilityOnly: true,
          networkTimeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        (await DocumentClient(
          http,
        ).get(server.baseUri).timeout(const Duration(seconds: 2))).text,
        'x',
      );
    } finally {
      finish.complete();
      http.close();
      scheduler.close();
      await server.close();
    }
  });
}

void _mediaTests() {
  test(
    'availability returns on media bytes without waiting for stream end',
    () async {
      final finish = Completer<void>();
      final server = await HttpTestServer.start((r) async {
        if (r.uri.path == '/index.m3u8') {
          r.response.write('#EXTM3U\n#EXTINF:8,\nmedia.ts\n#EXT-X-ENDLIST');
        } else {
          r.response.bufferOutput = false;
          r.response.headers.contentType = ContentType('video', 'mp2t');
          r.response.add(List.filled(188, 0x47));
          await r.response.flush();
          await finish.future;
        }
      });
      final http = MediaHttpClient();
      try {
        final result = await probeMedia(
          http,
          server.baseUri.resolve('index.m3u8'),
          HeaderPolicy({}),
          CancellationToken(),
          availabilityOnly: true,
          networkTimeout: const Duration(seconds: 1),
        ).timeout(const Duration(seconds: 2));
        expect(result.bytes, greaterThanOrEqualTo(188));
        expect(result.bytes, lessThan(1024));
        // The early exit must release the per-origin permit.
        await probeMedia(
          http,
          server.baseUri.resolve('media.ts'),
          HeaderPolicy({}),
          CancellationToken(),
          availabilityOnly: true,
        );
      } finally {
        finish.complete();
        http.close();
        await server.close();
      }
    },
  );
}

void _queueTests() {
  test(
    'scheduler queue does not consume document or probe network budget',
    () async {
      final server = await HttpTestServer.start((r) {
        r.response.add(List.filled(188, 0x47));
      });
      final scheduler = RequestScheduler(globalLimit: 1, originLimit: 1);
      final http = MediaHttpClient(scheduler: scheduler);
      try {
        for (final media in [false, true]) {
          final permit = await scheduler.acquire(server.baseUri);
          final future = media
              ? probeMedia(
                  http,
                  server.baseUri,
                  HeaderPolicy({}),
                  CancellationToken(),
                  availabilityOnly: true,
                  networkTimeout: const Duration(milliseconds: 150),
                )
              : DocumentClient(http).get(
                  server.baseUri,
                  networkTimeout: const Duration(milliseconds: 150),
                );
          await Future<void>.delayed(const Duration(milliseconds: 300));
          expect(server.calls['/'] ?? 0, media ? 1 : 0);
          permit.release();
          await future;
        }
      } finally {
        http.close();
        scheduler.close();
        await server.close();
      }
    },
  );

  test('queued cancellation releases without making a request', () async {
    final server = await HttpTestServer.start((r) => r.response.write('ok'));
    final scheduler = RequestScheduler(globalLimit: 1);
    final http = MediaHttpClient(scheduler: scheduler);
    final permit = await scheduler.acquire(server.baseUri);
    final token = CancellationToken();
    try {
      final future = probeMedia(
        http,
        server.baseUri,
        HeaderPolicy({}),
        token,
        availabilityOnly: true,
      );
      final expectation = expectLater(future, throwsA(isA<RequestCancelled>()));
      token.cancel();
      await expectation;
      permit.release();
      await DocumentClient(http).get(server.baseUri);
      expect(server.calls['/'], 1);
    } finally {
      permit.release();
      http.close();
      scheduler.close();
      await server.close();
    }
  });
}
