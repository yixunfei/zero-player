import 'dart:async';
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
    'late superseded searches cannot overwrite current results or status',
    () async {
      final oldStarted = Completer<void>();
      final releaseOld = Completer<void>();
      final oldFinished = Completer<void>();
      final server = await HttpTestServer.start((request) async {
        final query = request.uri.queryParameters['wd'];
        if (query == 'old') {
          oldStarted.complete();
          await releaseOld.future;
        }
        try {
          request.response.write(
            jsonEncode({
              'pagecount': 1,
              'list': [
                {'vod_id': query, 'vod_name': query},
                if (query == 'old') {'vod_id': 'old-2', 'vod_name': 'old-2'},
              ],
            }),
          );
        } finally {
          if (query == 'old') oldFinished.complete();
        }
      });
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      final sources = SourceRepository(db);
      final controller = SearchController(
        sources,
        DocumentClient(http),
        HistoryRepository(db),
      );
      addTearDown(() async {
        if (!releaseOld.isCompleted) releaseOld.complete();
        controller.dispose();
        http.close();
        await server.close();
        await db.close();
      });
      final id = await sources.saveManual('source', server.baseUri);
      final old = controller.search('old');
      await oldStarted.future;
      await controller.search('new');
      releaseOld.complete();
      await oldFinished.future;
      await old;
      expect(controller.query, 'new');
      expect(controller.items.map((item) => item.id), ['new']);
      expect(controller.statuses[id], '1 条结果');
      expect(controller.loading, isFalse);
    },
  );
}
