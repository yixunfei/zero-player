import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/discovery/presentation/discovery_page.dart';

void main() {
  late Directory root;
  late AppServices services;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('history-refresh-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.supervision.load();
    await services.settings.load();
    await services.settings.update({'recommendation': 'off'});
  });
  tearDown(() async {
    await services.close();
    await root.delete(recursive: true);
  });
  testWidgets(
    'history changes update continue watching without resetting the feed scroll',
    (tester) async {
      tester.view.physicalSize = const Size(320, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final episode = Episode(
        '第 1 集',
        Uri.parse('https://example.invalid/video.mp4'),
      );
      final line = PlayLine('线路', [episode]);
      final item = CatalogItem(
        sourceId: 'fixture',
        id: 'one',
        title: '续播测试',
        lines: [line],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DiscoveryPage(services: services)),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(
            find.byKey(const ValueKey('discovery-scroll')),
          )
          .controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      scroll.jumpTo(scroll.position.maxScrollExtent / 2);
      await tester.pump();
      final before = scroll.offset;
      expect(before, greaterThan(0));
      await tester.runAsync(
        () => services.history.save(
          item,
          line,
          episode,
          const Duration(seconds: 8),
          const Duration(seconds: 60),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('续播测试'), findsOneWidget);
      expect(find.textContaining('00:08'), findsOneWidget);
      expect(scroll.offset, before);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
