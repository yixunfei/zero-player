import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/data/source_diagnostics_store.dart';
import 'package:zero_player/features/sources/domain/source_diagnostics.dart';
import 'package:zero_player/features/sources/presentation/sources_page.dart';

void main() {
  late Directory root;
  late AppServices services;
  late String id;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('source-ui-');
    services = AppServices.scoped(
      root,
      AppDatabase.memory(),
      allowPrivateNetworks: true,
    );
    await services.settings.load();
    id = await services.sources.saveManual(
      '测试渠道',
      Uri.parse('https://example.test/api'),
    );
    await SourceDiagnosticsStore(services.db).save(
      id,
      SourceDiagnostics(
        state: 'inconclusive',
        checkedAt: DateTime(2026, 10, 28),
        addresses: const ['192.0.2.5'],
        tcpMs: 20,
        dnsMs: 3,
        port: 443,
      ),
    );
  });
  tearDown(() async {
    await services.close();
    await root.delete(recursive: true);
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets('favorites and source details work at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: SourcesPage(services: services)),
      );
      await tester.pumpAndSettle();
      expect(find.text('可能失效'), findsOneWidget);
      await tester.tap(find.byTooltip('收藏渠道'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('取消收藏渠道'), findsOneWidget);
      expect((await services.sources.find(id))!.favorite, isTrue);
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      expect(find.text('TCP Ping'), findsOneWidget);
      expect(find.text('192.0.2.5'), findsOneWidget);
      expect(find.text('cms / 443'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('停用可能失效'));
      await tester.pumpAndSettle();
      expect(find.text('停用 1 个可能失效渠道'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect((await services.sources.find(id))!.enabled, isTrue);
      await tester.tap(find.text('停用可能失效'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect((await services.sources.find(id))!.enabled, isFalse);
      expect((await services.sources.find(id))!.suppressed, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
