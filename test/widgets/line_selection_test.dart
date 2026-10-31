import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/presentation/line_selector.dart';
import '../../test_support/http_test_server.dart';

void main() {
  testWidgets(
    'default skips failed first line and manual failure needs confirmation',
    (tester) async {
      late Directory root;
      late AppServices services;
      late HttpTestServer server;
      late String source;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('zero-lines-');
        server = await HttpTestServer.start((r) {
          if (r.uri.path == '/bad.mp4') {
            r.response.statusCode = 404;
          } else {
            r.response.headers.contentType = ContentType('video', 'mp4');
            r.response.add([
              0,
              0,
              0,
              24,
              102,
              116,
              121,
              112,
              105,
              115,
              111,
              109,
            ]);
          }
        });
        services = AppServices.scoped(
          root,
          AppDatabase.memory(),
          allowPrivateNetworks: true,
        );
        HttpOverrides.runWithHttpOverrides(
          () => services.http,
          _RealHttpOverrides(),
        );
        await services.supervision.load();
        await services.settings.load();
        source = await services.sources.saveManual('test', server.baseUri);
      });
      var selected = -1;
      final item = CatalogItem(
        sourceId: source,
        id: 'm',
        title: 'Movie',
        lines: [
          PlayLine('broken', [Episode('1', server.baseUri.resolve('bad.mp4'))]),
          PlayLine('working', [
            Episode('1', server.baseUri.resolve('good.mp4')),
          ]),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => LineSelector(
                services: services,
                item: item,
                selected: selected,
                autoSelect: true,
                onSelected: (i) => setState(() => selected = i),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 100 && selected < 0; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      expect(
        selected,
        1,
        reason:
            '${server.calls} ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
      );
      await tester.tap(find.byType(ChoiceChip).first);
      await tester.pumpAndSettle();
      expect(find.text('线路尚未验证可用'), findsOneWidget);
      expect(selected, 1);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await services.close();
        await server.close();
        await root.delete(recursive: true);
      });
    },
  );
}

class _RealHttpOverrides extends HttpOverrides {}
