import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/presentation/feature_rule_dialog.dart';
import 'package:zero_player/features/settings/presentation/filter_resources_dialog.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/fingerprints/visual_fingerprint.dart';
import '../../test_support/fake_player_engine.dart';

const _viewports = [
  (320.0, 640.0, 1.6),
  (568.0, 320.0, 1.3),
  (390.0, 1000.0, 1.0),
  (1280.0, 1000.0, 1.0),
];

void main() {
  late Directory root;
  late AppServices services;
  late PlaybackController controller;
  late FeatureRule rule;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('filter-ui-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.supervision.load();
    await services.settings.load();
    controller = PlaybackController(services, FakePlayerEngine());
    rule = FeatureRule(
      id: 'ui',
      sourceId: 'channel',
      label: '测试标识',
      mode: FeatureMode.visual,
      sampleMs: 2000,
      beforeMs: 3000,
      afterMs: 15000,
      visual: List.filled(
        4,
        const VisualFingerprint('1234567890abcdef', [128, 50, 50], 30),
      ),
      audio: [],
      thumbnail: '',
      originKey: 'episode',
      originStartMs: 10000,
    );
    await services.filterFeatures.save(rule);
  });
  tearDown(() async {
    await controller.close();
    await services.close();
    await root.delete(recursive: true);
  });
  for (final (width, height, scale) in _viewports) {
    testWidgets('optional resources and editable feature preview at $width', (
      tester,
    ) async {
      _configureView(tester, Size(width, height), scale);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () => showFilterResources(context, services),
                      child: const Text('资源'),
                    ),
                    TextButton(
                      onPressed: () =>
                          editFeatureRule(context, controller, rule: rule),
                      child: const Text('编辑'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('资源'));
        await tester.pumpAndSettle();
        expect(find.text('手动下载'), findsNWidgets(3));
        expect(services.settings.value.filterOcr, isFalse);
        expect(services.settings.value.filterAsr, isFalse);
        expect(Directory('${root.path}/content_filter').existsSync(), isFalse);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('编辑'));
        await tester.pumpAndSettle();
        expect(find.textContaining('7.0–27.0'), findsOneWidget);
        await tester.ensureVisible(
          find.widgetWithText(TextField, '向前跳过（0–30 秒）'),
        );
        await tester.enterText(
          find.widgetWithText(TextField, '向前跳过（0–30 秒）'),
          '2',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('8.0–27.0'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('保存并应用'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect((await services.filterFeatures.list()).single.beforeMs, 2000);
        expect(services.settings.value.contentFilter, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }
}

void _configureView(WidgetTester tester, Size size, double scale) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
