import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/settings/presentation/content_filter_setting.dart';
import 'package:zero_player/media/content_filter/filter_strategy.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/mobile_app_fixture.dart';

void main() {
  _authorizationDisplayTest();
  testWidgets(
    'keyword settings fit narrow large-text display and persist skip duration',
    (tester) async {
      final fixture = MobileAppFixture();
      await tester.runAsync(fixture.initialize);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [ContentFilterSetting(services: fixture.services)],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final selector = find.byType(DropdownButton<int>);
        await tester.ensureVisible(selector);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.widget<DropdownButton<int>>(selector).onChanged!(30);
        await fixture.settle(tester);
        expect(fixture.services.settings.value.filterSkipSeconds, 30);
        await tester.runAsync(fixture.services.settings.load);
        expect(fixture.services.settings.value.filterSkipSeconds, 30);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.finish(tester);
      }
    },
  );
}

void _authorizationDisplayTest() {
  testWidgets(
    'cancelled or rejected authorization leaves committed dropdown values',
    (tester) async {
      final fixture = MobileAppFixture();
      await tester.runAsync(() async {
        await fixture.initialize();
        final guard = fixture.services.supervision;
        await guard.saveCredentials(
          await guard.prepareCredentials('test-password'),
        );
        await guard.execute(
          SensitiveOperation.supervision,
          () => fixture.services.installationAccess.setContentFilterProtection(
            true,
          ),
          password: 'test-password',
        );
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [ContentFilterSetting(services: fixture.services)],
              ),
            ),
          ),
        );
        final seconds = find.byType(DropdownButton<int>);
        await tester.ensureVisible(seconds);
        await tester.tap(seconds);
        await tester.pumpAndSettle();
        await tester.tap(find.text('30 秒').last);
        await fixture.settle(tester);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(tester.widget<DropdownButton<int>>(seconds).value, 20);
        expect(fixture.services.settings.value.filterSkipSeconds, 20);
        final strategy = find.byType(DropdownButton<FilterStrategy>);
        await tester.ensureVisible(strategy);
        await tester.tap(strategy);
        await tester.pumpAndSettle();
        await tester.tap(find.text(FilterStrategy.confirm.label).last);
        await fixture.settle(tester);
        await tester.enterText(find.byType(TextField), 'wrong-password');
        await tester.runAsync(() => tester.tap(find.text('验证并继续')));
        await fixture.settle(tester);
        expect(
          tester.widget<DropdownButton<FilterStrategy>>(strategy).value,
          FilterStrategy.conservative,
        );
        expect(fixture.services.settings.value.filterStrategy, 'conservative');
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.finish(tester);
      }
    },
  );
}
