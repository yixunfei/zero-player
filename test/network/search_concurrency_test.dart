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
    'configured concurrency bounds requests and merges source results',
    () async {
      var active = 0, peak = 0;
      final server = await HttpTestServer.start((request) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        request.response.write(
          jsonEncode({
            'pagecount': 1,
            'list': [
              {
                'vod_id': '1',
                'vod_name': '合并测试',
                'vod_year': '2026',
                'type_name': request.uri.path == '/1' ? '电视剧' : '国产剧',
              },
            ],
          }),
        );
        active--;
      });
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      final sources = SourceRepository(db);
      final search = SearchController(
        sources,
        DocumentClient(http),
        HistoryRepository(db),
      );
      try {
        for (var i = 0; i < 4; i++) {
          await sources.saveManual('source$i', server.baseUri.resolve('$i'));
        }
        await search.search('合并测试', concurrency: 2);
        expect(peak, 2);
        expect(search.groups.length, 1);
        expect(search.groups.values.single.length, 4);
        peak = 0;
        await search.search('合并测试', concurrency: 1);
        expect(peak, 1);
        final blocked = search.items.first.sourceId;
        await search.blockSource(blocked);
        expect(search.items.where((i) => i.sourceId == blocked), isEmpty);
        expect((await sources.find(blocked))!.enabled, isFalse);
      } finally {
        search.dispose();
        http.close();
        await server.close();
        await db.close();
      }
    },
  );
}
