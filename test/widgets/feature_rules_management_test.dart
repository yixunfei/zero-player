import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/presentation/feature_rules_dialog.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/fingerprints/visual_fingerprint.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  late _Fixture fixture;
  setUp(() async {
    fixture = _Fixture();
    await fixture.create();
  });
  tearDown(() async {
    await fixture.close();
  });
  _passwordSessionTest(() => fixture);
  for (final size in [const Size(320, 640), const Size(568, 320)]) {
    testWidgets(
      'feature management edits scope, toggles and deletes at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showFeatureRules(context, fixture.player),
                    child: const Text('管理'),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() => tester.tap(find.text('管理')));
          await _settle(tester);
          expect(tester.takeException(), isNull);
          await _tap(tester, find.text('预览 / 编辑'));
          final scope = find.byType(DropdownButtonFormField<FeatureScope>);
          await tester.ensureVisible(scope);
          tester
              .widget<DropdownButtonFormField<FeatureScope>>(scope)
              .onChanged!(FeatureScope.series);
          await tester.pumpAndSettle();
          await _tap(tester, find.text('保存并应用'));
          expect(
            (await fixture.services.filterFeatures.list()).single.scope,
            FeatureScope.series,
          );
          await tester.ensureVisible(find.byType(SwitchListTile));
          await tester.runAsync(() async {
            tester
                .widget<SwitchListTile>(find.byType(SwitchListTile))
                .onChanged!(false);
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await _settle(tester);
          expect(
            (await fixture.services.filterFeatures.list()).single.enabled,
            isFalse,
          );
          await _tap(tester, find.text('删除'));
          expect(find.text('删除内容特征'), findsOneWidget);
          await tester.runAsync(
            () => tester.tap(find.widgetWithText(FilledButton, '删除')),
          );
          await _settle(tester);
          expect(await fixture.services.filterFeatures.list(), isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }
}

void _passwordSessionTest(_Fixture Function() fixture) {
  testWidgets(
    'one password covers management edits and closing revokes access',
    (tester) async {
      final f = fixture();
      final guard = f.services.supervision;
      await tester.runAsync(() async {
        final credentials = await guard.prepareCredentials(
          'management-password',
        );
        await guard.saveCredentials(credentials);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFeatureRules(context, f.player),
                child: const Text('管理'),
              ),
            ),
          ),
        ),
      );
      await _tap(tester, find.text('管理'));
      expect(find.text('验证监管密码'), findsOneWidget);
      expect(find.text('内容特征管理'), findsNothing);
      await tester.enterText(find.byType(TextField), 'management-password');
      await _tap(tester, find.text('验证并继续'));
      expect(find.text('内容特征管理'), findsOneWidget);
      await _tap(tester, find.text('预览 / 编辑'));
      await tester.enterText(find.widgetWithText(TextField, '测试特征'), '已修改名称');
      await _tap(tester, find.text('保存并应用'));
      expect(find.text('验证监管密码'), findsNothing);
      expect((await f.services.filterFeatures.list()).single.label, '已修改名称');
      await _tap(tester, find.byType(SwitchListTile));
      expect((await f.services.filterFeatures.list()).single.enabled, isFalse);
      expect(find.text('验证监管密码'), findsNothing);
      await _tap(tester, find.text('完成'));
      await _tap(tester, find.text('管理'));
      expect(find.text('验证监管密码'), findsOneWidget);
      await _tap(tester, find.text('取消'));
      expect(find.text('内容特征管理'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.runAsync(() => tester.tap(finder));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

final class _Fixture {
  late Directory root;
  late AppServices services;
  late PlaybackController player;
  Future<void> create() async {
    root = await Directory.systemTemp.createTemp('feature-management-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.settings.load();
    await services.supervision.load();
    player = PlaybackController(services, FakePlayerEngine());
    player.request = PlaybackRequest(
      CatalogItem(
        sourceId: 'channel',
        id: 'show',
        title: 'Show',
        lines: [
          PlayLine('main', [
            Episode('1', Uri.parse('https://example.org/1.mp4')),
          ]),
        ],
      ),
    );
    await services.filterFeatures.save(
      FeatureRule(
        id: 'rule',
        sourceId: 'channel',
        label: '测试特征',
        mode: FeatureMode.visual,
        sampleMs: 2000,
        beforeMs: 0,
        afterMs: 20000,
        visual: List.filled(
          4,
          const VisualFingerprint('1234567890abcdef', [128, 50, 50], 30),
        ),
        audio: [],
        thumbnail: '',
        originKey: player.workKey,
        originStartMs: 5000,
        seriesKey: player.featureSeriesKey,
      ),
    );
  }

  Future<void> close() async {
    player.request = null;
    await player.close();
    await services.close();
    await root.delete(recursive: true);
  }
}
