import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/library/data/history_repository.dart';
import 'package:zero_player/features/search/application/search_controller.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'preferred source starts first; scope and retry respect disabled sources',
    () async {
      final requests = <String>[];
      var fail = true;
      final server = await HttpTestServer.start((request) async {
        requests.add(request.uri.path);
        if (fail && request.uri.path == '/retry') {
          request.response.statusCode = 503;
        } else {
          request.response.write(
            jsonEncode({
              'pagecount': 1,
              'list': [
                {'vod_id': '1', 'vod_name': '电影', 'vod_year': '2026'},
              ],
            }),
          );
        }
      });
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final sources = SourceRepository(db);
      final search = SearchController(
        sources,
        DocumentClient(http),
        HistoryRepository(db),
      );
      addTearDown(() async {
        search.dispose();
        http.close();
        await server.close();
        await db.close();
      });
      for (final name in ['other', 'preferred', 'retry']) {
        await sources.saveManual(name, server.baseUri.resolve(name));
      }
      final preferred = (await sources.all())
          .firstWhere((s) => s.name == 'preferred')
          .id;
      await search.search('电影', concurrency: 1, preferredSourceId: preferred);
      expect(requests.first, '/preferred');
      expect(search.groups.values.single.first.sourceId, preferred);
      expect(search.failedSources.length, 1);
      final before = search.items.length;
      requests.clear();
      fail = false;
      await search.retryFailed();
      expect(requests.toSet(), {'/retry'});
      expect(search.items.length, before + 1);
      expect(search.failedSources, isEmpty);
      requests.clear();
      await search.search(
        '电影',
        preferredSourceId: preferred,
        onlyPreferred: true,
      );
      expect(requests, ['/preferred']);
      await sources.setEnabled(preferred, false);
      requests.clear();
      await search.search(
        '电影',
        preferredSourceId: preferred,
        onlyPreferred: true,
      );
      expect(requests, isEmpty);
      expect(search.error, isNotNull);
    },
  );
}
