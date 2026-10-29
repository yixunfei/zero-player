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
    'entry, favorite, verified, unknown order drives requests and results',
    () async {
      final requested = <String>[];
      final server = await HttpTestServer.start((request) {
        requested.add(request.uri.path.substring(1));
        request.response.write(
          jsonEncode({
            'pagecount': 1,
            'list': [
              {'vod_id': '1', 'vod_name': '电影', 'vod_year': '2026'},
            ],
          }),
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
      addTearDown(() async {
        search.dispose();
        http.close();
        await server.close();
        await db.close();
      });
      final ids = <String, String>{};
      for (final name in [
        'unknown',
        'verified',
        'favorite',
        'entry',
        'disabled',
      ]) {
        ids[name] = await sources.saveManual(
          name,
          server.baseUri.resolve(name),
        );
      }
      await sources.favorite(ids['favorite']!, true);
      await sources.favorite(ids['disabled']!, true);
      await sources.setEnabled(ids['disabled']!, false);
      await sources.health(ids['verified']!, null, latencyMs: 1);
      await search.search(
        '电影',
        concurrency: 1,
        preferredSourceId: ids['entry'],
      );
      expect(requested, ['entry', 'favorite', 'verified', 'unknown']);
      expect(
        search.groups.values.single.map((i) => i.sourceId),
        ['entry', 'favorite', 'verified', 'unknown'].map((name) => ids[name]),
      );
      expect(search.sourceLabels[ids['favorite']], '收藏渠道');
      await sources.favorite(ids['unknown']!, true);
      requested.clear();
      await search.search(
        '电影',
        concurrency: 1,
        preferredSourceId: ids['entry'],
      );
      expect(requested.first, 'entry');
      expect(
        requested.indexOf('unknown'),
        lessThan(requested.indexOf('verified')),
      );
    },
  );
}
