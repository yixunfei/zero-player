import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/request_scheduler.dart';
import '../../test_support/http_test_server.dart';

void main() {
  final uri = Uri.parse('https://test.invalid');
  const chinese = [0xd6, 0xd0, 0xce, 0xc4];
  test(
    'GBK and GB2312 headers, HTML declarations and strict fallback decode Chinese',
    () {
      for (final charset in ['GBK', 'gb2312', 'gb18030']) {
        expect(
          Document(
            uri,
            chinese,
            contentType: 'text/html; charset=$charset',
          ).text,
          '中文',
        );
      }
      expect(
        Document(uri, [
          ...ascii.encode('<meta charset="gbk">'),
          ...chinese,
        ]).text,
        '<meta charset="gbk">中文',
      );
      expect(Document(uri, chinese).text, '中文');
      expect(
        Document(uri, [0xef, 0xbb, 0xbf, ...utf8.encode('中文')]).text,
        '中文',
      );
      expect(
        () => Document(
          uri,
          chinese,
          contentType: 'text/html; charset=utf-8',
        ).text,
        throwsFormatException,
      );
      expect(
        () => Document(uri, [
          0x90,
          0x30,
          0x81,
          0x30,
        ], contentType: 'text/html; charset=gb18030').text,
        throwsFormatException,
      );
    },
  );

  test(
    'content encoding is case insensitive and decoded in reverse order',
    () async {
      final server = await HttpTestServer.start((request) {
        request.response.headers.set('content-encoding', 'GZip, Deflate');
        request.response.headers.set('content-type', 'text/plain; charset=GBK');
        request.response.add(zlib.encode(gzip.encode(chinese)));
      });
      final http = MediaHttpClient();
      addTearDown(http.close);
      addTearDown(server.close);
      expect((await DocumentClient(http).get(server.baseUri)).text, '中文');
    },
  );

  test(
    'unsupported encoding cancels body and releases the sole network permit',
    () async {
      final server = await HttpTestServer.start((request) {
        if (request.uri.path == '/unsupported') {
          request.response.headers.set('content-encoding', 'gzip, br');
        }
        request.response.write('ok');
      });
      final scheduler = RequestScheduler(globalLimit: 1);
      final http = MediaHttpClient(scheduler: scheduler);
      addTearDown(http.close);
      addTearDown(scheduler.close);
      addTearDown(server.close);
      final client = DocumentClient(http);
      await expectLater(
        client.get(server.baseUri.resolve('unsupported')),
        throwsA(
          isA<RemoteFailure>().having(
            (failure) => failure.kind,
            'kind',
            FailureKind.unsupported,
          ),
        ),
      );
      expect((await client.get(server.baseUri)).text, 'ok');
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}
