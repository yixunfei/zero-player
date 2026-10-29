import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/installation_introduction.dart';
import 'package:zero_player/core/persistence/installation_metadata.dart';
import 'package:zero_player/features/settings/presentation/adult_filter_setting.dart';
import 'package:zero_player/features/settings/presentation/content_filter_protection.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';
import 'package:zero_player/features/supervision/application/content_policy.dart';
import 'package:zero_player/features/supervision/application/installation_access.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/mobile_app_fixture.dart';

void main() {
  _introductionTests();
  _adultDialogTests();
  _protectionSwitchTests();
}

void _introductionTests() {
  testWidgets(
    'first run offers optional supervision without asking for a password',
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
          InstallationIntroduction(
            services: fixture.services,
            child: const MaterialApp(home: Text('product ready')),
          ),
        );
        expect(find.text('是否设置监管模式？'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        await tester.ensureVisible(find.text('暂不设置，开始使用'));
        await tester.runAsync(() async {
          await tester.tap(find.text('暂不设置，开始使用'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(find.text('product ready'), findsOneWidget);
        expect(fixture.services.supervision.configured, isFalse);
        expect(fixture.services.installationAccess.adultVerified, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.finish(tester);
      }
    },
  );
  testWidgets(
    'initial supervision route can be cancelled without completing the prompt',
    (tester) async {
      final fixture = MobileAppFixture();
      await tester.runAsync(fixture.initialize);
      try {
        await tester.pumpWidget(
          InstallationIntroduction(
            services: fixture.services,
            child: const MaterialApp(home: Text('product ready')),
          ),
        );
        await tester.tap(find.text('现在设置监管'));
        await tester.pumpAndSettle();
        expect(find.text('首次设置密码和恢复码'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('是否设置监管模式？'), findsOneWidget);
        expect(fixture.services.installationAccess.introductionSeen, isFalse);
      } finally {
        await fixture.finish(tester);
      }
    },
  );
}

void _adultDialogTests() {
  testWidgets(
    'adult switch rejects cancellation and errors, then remembers successful access',
    (tester) async {
      final fixture = MobileAppFixture();
      await tester.runAsync(fixture.initialize);
      final access = InstallationAccess(
        fixture.services.db,
        verifyPassword: (value) async => value == 'fixture',
      );
      await tester.runAsync(access.load);
      final settings = SettingsController(
        fixture.services.db,
        prepareAuthorization: access.load,
        authorizeAdultDisable: access.requireAdultAccess,
        adultFilterRequired: () => fixture.services.supervision.enabled,
      );
      await tester.runAsync(settings.load);
      final policy = ContentPolicy(settings, fixture.services.supervision);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdultFilterSetting(policy: policy, access: access),
            ),
          ),
        );
        await tester.runAsync(() => tester.tap(find.byType(SwitchListTile)));
        await fixture.settle(tester);
        expect(find.text('首次关闭成人过滤'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).obscureText,
          isTrue,
        );
        await tester.runAsync(() => tester.tap(find.text('取消')));
        await fixture.settle(tester);
        expect(access.adultVerified, isFalse);
        expect(settings.value.filterAdult, isTrue);
        await tester.runAsync(() => tester.tap(find.byType(SwitchListTile)));
        await fixture.settle(tester);
        await tester.enterText(find.byType(TextField), 'wrong');
        await tester.runAsync(() => tester.tap(find.text('验证并关闭过滤')));
        await fixture.settle(tester);
        expect(find.text('访问密码不正确'), findsOneWidget);
        expect(access.adultVerified, isFalse);
        await tester.enterText(find.byType(TextField), 'fixture');
        await tester.runAsync(() => tester.tap(find.text('验证并关闭过滤')));
        await fixture.waitFor(tester, () => !settings.value.filterAdult);
        await tester.pumpAndSettle();
        expect(access.adultVerified, isTrue);
        expect(find.byType(AlertDialog), findsNothing);
        expect(settings.value.filterAdult, isFalse);
        await tester.runAsync(() => tester.tap(find.byType(SwitchListTile)));
        await fixture.waitFor(tester, () => settings.value.filterAdult);
        await tester.pumpAndSettle();
        expect(settings.value.filterAdult, isTrue);
        await tester.runAsync(() => tester.tap(find.byType(SwitchListTile)));
        await fixture.waitFor(tester, () => !settings.value.filterAdult);
        await tester.pumpAndSettle();
        expect(settings.value.filterAdult, isFalse);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        policy.dispose();
        await tester.runAsync(() async {
          await settings.close();
          await access.close();
        });
        await fixture.finish(tester);
      }
    },
  );
}

void _protectionSwitchTests() {
  testWidgets(
    'protection switch always authenticates including when supervision is disabled',
    (tester) async {
      final fixture = MobileAppFixture();
      await tester.runAsync(() async {
        await fixture.initialize();
        final guard = fixture.services.supervision;
        await guard.saveCredentials(
          await guard.prepareCredentials('fixture-password'),
        );
        await guard.execute(
          SensitiveOperation.supervision,
          () => guard.setEnabled(false),
          password: 'fixture-password',
        );
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ContentFilterProtection(services: fixture.services),
            ),
          ),
        );
        expect(
          fixture.services.installationAccess.protectContentFilter,
          isFalse,
        );
        await tester.tap(find.byType(SwitchListTile));
        await fixture.settle(tester);
        expect(find.text('验证监管密码'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(
          fixture.services.installationAccess.protectContentFilter,
          isFalse,
        );
        await tester.tap(find.byType(SwitchListTile));
        await fixture.settle(tester);
        await tester.enterText(find.byType(TextField), 'fixture-password');
        await tester.runAsync(() async {
          await tester.tap(find.text('验证并继续'));
          await Future<void>.delayed(const Duration(seconds: 1));
        });
        await fixture.waitFor(
          tester,
          () => fixture.services.installationAccess.protectContentFilter,
        );
        final stored = await tester.runAsync(
          () => fixture.services.db.rows(
            'SELECT value FROM app_meta WHERE key=?',
            [installationAccessKey],
          ),
        );
        expect(
          (jsonDecode(stored!.single['value'] as String)
              as Map)['protectContentFilter'],
          isTrue,
        );
        await tester.tap(find.byType(SwitchListTile));
        await fixture.settle(tester);
        expect(find.text('验证监管密码'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      } finally {
        await fixture.finish(tester);
      }
    },
  );
}
