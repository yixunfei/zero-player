import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/file_response.dart';

import '../../test_support/http_test_server.dart';

void main() {
  late Directory directory;
  late File file;
  late HttpTestServer server;
  late HttpClient client;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('file-response-');
    file = await File('${directory.path}/media').writeAsBytes([1, 2, 3, 4]);
    server = await HttpTestServer.start((request) async {
      try {
        await serveLocalFile(request, file, contentType: 'video/mp4');
      } catch (_) {
        request.response.statusCode = 500;
      }
    });
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.close();
    await directory.delete(recursive: true);
  });

  Future<HttpClientResponse> get(String range, {String method = 'GET'}) async {
    final request = await client.openUrl(method, server.baseUri);
    request.headers.set('range', range);
    return request.close();
  }

  for (final range in [
    'bytes=0-999999999999999999999999',
    'bytes=-999999999999999999999999',
  ]) {
    test('oversized end or suffix is clamped: $range', () async {
      final response = await get(range);
      expect(response.statusCode, 206);
      expect(response.headers.value('content-range'), 'bytes 0-3/4');
      expect(await response.expand((chunk) => chunk).toList(), [1, 2, 3, 4]);
    });
  }

  for (final range in [
    'bytes=999999999999999999999999-',
    'bytes=4-',
    'bytes=2-1',
    'bytes=-0',
    'bytes=-',
    'bytes=bad',
  ]) {
    test('unsatisfiable range includes file size: $range', () async {
      final response = await get(range);
      expect(response.statusCode, 416);
      expect(response.headers.value('content-range'), 'bytes */4');
      await response.drain<void>();
    });
  }

  test('range against an empty file is rejected without throwing', () async {
    await file.writeAsBytes([]);
    final response = await get('bytes=0-0');
    expect(response.statusCode, 416);
    expect(response.headers.value('content-range'), 'bytes */0');
    await response.drain<void>();
  });

  test('HEAD preserves partial response headers without a body', () async {
    final response = await get('bytes=1-2', method: 'HEAD');
    expect(response.statusCode, 206);
    expect(response.contentLength, 2);
    expect(response.headers.value('content-range'), 'bytes 1-2/4');
    expect(await response.expand((chunk) => chunk).toList(), isEmpty);
  });
}
