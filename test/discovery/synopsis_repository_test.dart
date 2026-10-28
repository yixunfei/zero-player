import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/discovery/data/synopsis_repository.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'extracts only synopsis, decodes entities and rejects verification pages',
    () {
      expect(
        parseSynopsis('<span property="v:summary">故事 &amp; 旅途<br> 继续。</span>'),
        '故事 & 旅途 继续。',
      );
      expect(
        () => parseSynopsis('<form action="/c"></form>'),
        throwsFormatException,
      );
      expect(
        () => parseSynopsis('<title>豆瓣</title><p>loading</p>'),
        throwsFormatException,
      );
    },
  );
  test(
    'deduplicates requests, persists successes and backs off failed pages',
    () async {
      final server = await HttpTestServer.start((r) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        r.response.write(
          r.uri.path == '/1/'
              ? '<span property="v:summary">真实简介</span>'
              : '<form action="/c"></form>',
        );
      });
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      SynopsisRepository repository() => SynopsisRepository(
        DocumentClient(http),
        db,
        endpoint: (id) => server.baseUri.resolve('$id/'),
      );
      final first = repository();
      final second = repository();
      try {
        expect(await Future.wait([first.get('1'), first.get('1')]), [
          '真实简介',
          '真实简介',
        ]);
        expect(server.calls['/1/'], 1);
        expect(await second.get('1'), '真实简介');
        expect(server.calls['/1/'], 1);
        await expectLater(first.get('2'), throwsFormatException);
        await expectLater(first.get('2'), throwsFormatException);
        expect(server.calls['/2/'], 1);
      } finally {
        await first.close();
        await second.close();
        http.close();
        await db.close();
        await server.close();
      }
    },
  );
}
