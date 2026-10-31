import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/library/data/history_repository.dart';
import 'package:zero_player/features/search/application/search_controller.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/media/network/media_probe.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'failed channels lose priority, stay blocked, and can be restored',
    () async {
      final calls = <String>[];
      final server = await HttpTestServer.start((request) {
        calls.add(request.uri.path);
        request.response.write(
          request.uri.path == '/bad'
              ? 'invalid'
              : jsonEncode({'list': [], 'pagecount': 1}),
        );
      });
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final sources = SourceRepository(db);
      final search = SearchController(
        sources,
        DocumentClient(http),
        HistoryRepository(db),
      );
      try {
        final bad = await sources.saveManual(
          'A failing',
          server.baseUri.resolve('bad'),
        );
        final good = await sources.saveManual(
          'B working',
          server.baseUri.resolve('good'),
        );
        await search.search('test', concurrency: 1);
        expect(search.failedSources, contains(bad));
        expect(search.latencies[good], greaterThanOrEqualTo(0));
        calls.clear();
        await search.search('test', concurrency: 1);
        expect(calls, ['/good', '/bad']);
        await search.blockSource(bad);
        expect((await SourceRepository(db).find(bad))!.enabled, isFalse);
        await sources.setEnabled(bad, true);
        expect((await sources.find(bad))!.available, isTrue);
      } finally {
        search.dispose();
        http.close();
        await server.close();
        await db.close();
      }
    },
  );
  test(
    'media probe rejects HTML and empty success, caps received sample',
    () async {
      final server = await HttpTestServer.start((request) {
        if (request.uri.path == '/html') {
          request.response.headers.contentType = ContentType.html;
          request.response.write('<html>error</html>');
        } else if (request.uri.path == '/video') {
          request.response.add(List.filled(512 * 1024, 0x47));
        }
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      try {
        for (final path in ['html', 'empty']) {
          await expectLater(
            probeMedia(
              http,
              server.baseUri.resolve(path),
              HeaderPolicy({}),
              CancellationToken(),
            ),
            throwsFormatException,
          );
        }
        final result = await probeMedia(
          http,
          server.baseUri.resolve('video'),
          HeaderPolicy({}),
          CancellationToken(),
          maxBytes: 64 * 1024,
        );
        expect(result.bytes, 64 * 1024);
      } finally {
        http.close();
        await server.close();
      }
    },
  );
}
