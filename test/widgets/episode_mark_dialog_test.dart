import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/presentation/feature_rule_dialog.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  late Directory root;
  late AppServices services;
  late FakePlayerEngine engine;
  late PlaybackController player;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mark-dialog-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.settings.load();
    await services.supervision.load();
    await services.gateway.start();
    engine = FakePlayerEngine();
    player = PlaybackController(services, engine);
    await player.open(
      PlaybackRequest(
        CatalogItem(
          sourceId: 's',
          id: 'm',
          title: '测试',
          lines: [
            PlayLine('main', [
              Episode('1', Uri.parse('https://example.org/m.mp4')),
            ]),
          ],
        ),
      ),
    );
    await player.seek(const Duration(seconds: 8));
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    await player.close();
    await services.close();
    await root.delete(recursive: true);
  });
  for (final (width, height, scale) in [
    (320.0, 640.0, 1.6),
    (568.0, 320.0, 1.3),
    (1280.0, 900.0, 1.0),
  ]) {
    testWidgets('direct mark and cancellation without extraction at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      try {
        await _mount(tester, player);
        await tester.tap(find.text('标记'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(await services.skips.list(player.workKey), isEmpty);
        await tester.tap(find.text('标记'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(TextField, '向后跳过（0–120 秒）'),
        );
        await tester.enterText(
          find.widgetWithText(TextField, '向后跳过（0–120 秒）'),
          '4',
        );
        await tester.pump();
        await tester.runAsync(() async {
          await tester.tap(find.text('仅保存本集区间'));
          await Future<void>.delayed(const Duration(milliseconds: 120));
        });
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          (await services.skips.list(player.workKey)).single.end,
          const Duration(seconds: 12),
        );
        expect(engine.seeks.last, const Duration(seconds: 12));
        expect(await services.filterFeatures.list(), isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }
}

Future<void> _mount(WidgetTester tester, PlaybackController player) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editFeatureRule(context, player),
              child: const Text('标记'),
            ),
          ),
        ),
      ),
    );
