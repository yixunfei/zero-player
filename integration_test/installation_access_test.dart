import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/installation_introduction.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/settings/presentation/adult_filter_setting.dart';
import 'package:zero_player/features/settings/presentation/content_filter_protection.dart';
import 'package:zero_player/features/settings/presentation/backup_restore.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';

const _testPassword = 'native-supervision-password';
const _adultPassword = String.fromEnvironment('ADULT_ACCESS_TEST_PASSWORD');
late AppServices _services;
late Directory _root;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    _root = await Directory.systemTemp.createTemp('install-access-');
    _services = AppServices.scoped(
      _root,
      AppDatabase(File('${_root.path}/test.sqlite')),
    );
    await _services.supervision.load();
    await _services.settings.load();
    await _services.platform.initialize();
  });
  tearDown(() async {
    await _services.close();
    await _root.delete(recursive: true);
  });
  _restoreCase();
  testWidgets(
    'fresh startup configures supervision and keeps adult filter locked',
    (tester) async {
      await _mount(tester, introduction: true);
      expect(find.text('是否设置监管模式？'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      if (Platform.isWindows) expect(await windowManager.isVisible(), isTrue);
      await _tap(tester, find.text('现在设置监管'));
      await _tap(tester, find.text('首次设置密码和恢复码'));
      await _enter(tester, find.byType(TextField).at(0), _testPassword);
      await _enter(tester, find.byType(TextField).at(1), _testPassword);
      await _tap(tester, find.text('生成恢复码'));
      await _until(tester, () => find.text('保存恢复码').evaluate().isNotEmpty);
      await _tap(tester, find.byType(Checkbox));
      await _tap(tester, find.text('完成设置'));
      await _until(tester, () => _services.supervision.configured);
      await tester.pageBack();
      await _until(tester, () => _services.installationAccess.introductionSeen);
      await tester.pumpAndSettle();
      expect(find.text('是否设置监管模式？'), findsNothing);
      expect(_adultSwitch(tester).onChanged, isNull);
      expect(_services.contentPolicy.filterAdult, isTrue);
      expect(_services.installationAccess.adultVerified, isFalse);
      await _protection(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'native verifier rejects wrong password and persists first adult access',
    (tester) async {
      await _mount(tester, introduction: true);
      await _tap(tester, find.text('暂不设置，开始使用'));
      await _until(tester, () => _services.installationAccess.introductionSeen);
      await _tap(tester, find.text('成人源与内容关键词过滤'));
      await _until(tester, () => find.text('首次关闭成人过滤').evaluate().isNotEmpty);
      await _tap(tester, find.text('取消'));
      expect(_services.settings.value.filterAdult, isTrue);
      await _tap(tester, find.text('成人源与内容关键词过滤'));
      await _enter(tester, find.byType(TextField), 'incorrect-native-password');
      await _tap(tester, find.text('验证并关闭过滤'));
      await _until(tester, () => find.text('访问密码不正确').evaluate().isNotEmpty);
      expect(_services.installationAccess.adultVerified, isFalse);
      await _enter(tester, find.byType(TextField), _adultPassword);
      await _tap(tester, find.text('验证并关闭过滤'));
      await _until(tester, () => !_services.settings.value.filterAdult);
      await _tap(tester, find.text('成人源与内容关键词过滤'));
      await _until(tester, () => _services.settings.value.filterAdult);
      await _tap(tester, find.text('成人源与内容关键词过滤'));
      await _until(tester, () => !_services.settings.value.filterAdult);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await _services.close();
      _services = AppServices.scoped(
        _root,
        AppDatabase(File('${_root.path}/test.sqlite')),
      );
      await _services.supervision.load();
      await _services.settings.load();
      await _mount(tester, introduction: true);
      expect(find.text('是否设置监管模式？'), findsNothing);
      expect(_services.installationAccess.adultVerified, isTrue);
      expect(_services.settings.value.filterAdult, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
    skip: _adultPassword.isEmpty,
  );
}

void _restoreCase() {
  testWidgets(
    'backup restore requires local consent without weakening supervision',
    (tester) async {
      final data = jsonDecode(await _services.backup.export()) as Map;
      data['tables']['settings'] = [
        {'key': 'filterAdult', 'value': 'false'},
        {'key': 'filterSkipSeconds', 'value': '30'},
      ];
      final preview = await _services.backup.preview(jsonEncode(data));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    confirmBackupRestore(context, _services, preview),
                child: const Text('restore fixture'),
              ),
            ),
          ),
        ),
      );
      await _tap(tester, find.text('restore fixture'));
      await _tap(tester, find.text('确认'));
      await _until(
        tester,
        () => find.text('验证备份中的成人过滤设置').evaluate().isNotEmpty,
      );
      await _tap(tester, find.text('取消'));
      expect(_services.settings.value.filterAdult, isTrue);
      expect(_services.settings.value.filterSkipSeconds, 20);
      await _tap(tester, find.text('restore fixture'));
      await _tap(tester, find.text('确认'));
      await _until(tester, () => find.byType(TextField).evaluate().isNotEmpty);
      await _enter(tester, find.byType(TextField), 'wrong-backup-password');
      await _tap(tester, find.text('验证并继续恢复'));
      await _until(tester, () => find.text('访问密码不正确').evaluate().isNotEmpty);
      expect(_services.settings.value.filterSkipSeconds, 20);
      await _enter(tester, find.byType(TextField), _adultPassword);
      await _tap(tester, find.text('验证并继续恢复'));
      await _until(
        tester,
        () => _services.settings.value.filterSkipSeconds == 30,
      );
      expect(_services.settings.value.filterAdult, isFalse);
      expect(_services.installationAccess.adultVerified, isTrue);
      final guard = _services.supervision;
      await _services.settings.update({'filterSkipSeconds': 45});
      await guard.saveCredentials(
        await guard.prepareCredentials(_testPassword),
      );
      await _tap(tester, find.text('restore fixture'));
      await _tap(tester, find.text('确认'));
      await _until(tester, () => find.text('验证监管密码').evaluate().isNotEmpty);
      await _enter(tester, find.byType(TextField), _testPassword);
      await _tap(tester, find.text('验证并继续'));
      await _until(
        tester,
        () => _services.settings.value.filterSkipSeconds == 30,
      );
      expect(_services.contentPolicy.filterAdult, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
    skip: _adultPassword.isEmpty,
  );
}

Future<void> _mount(WidgetTester tester, {required bool introduction}) async {
  final settings = MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [
          AdultFilterSetting(
            policy: _services.contentPolicy,
            access: _services.installationAccess,
          ),
          ContentFilterProtection(services: _services),
        ],
      ),
    ),
  );
  await tester.pumpWidget(
    introduction
        ? InstallationIntroduction(services: _services, child: settings)
        : settings,
  );
  await tester.pump(const Duration(milliseconds: 150));
}

SwitchListTile _adultSwitch(WidgetTester tester) => tester
    .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '成人源与内容关键词过滤'));

Future<void> _protection(WidgetTester tester) async {
  final access = _services.installationAccess;
  final guard = _services.supervision;
  expect(access.protectContentFilter, isFalse);
  await _services.settings.update({'filterSkipSeconds': 30});
  await _tap(tester, find.text('内容过滤设置需要监管验证'));
  await _until(tester, () => find.text('验证监管密码').evaluate().isNotEmpty);
  await _tap(tester, find.text('取消'));
  expect(access.protectContentFilter, isFalse);
  await _tap(tester, find.text('内容过滤设置需要监管验证'));
  await _until(tester, () => find.byType(TextField).evaluate().isNotEmpty);
  await _enter(tester, find.byType(TextField), _testPassword);
  await _tap(tester, find.text('验证并继续'));
  await _until(tester, () => access.protectContentFilter);
  await expectLater(
    _services.settings.update({'filterSkipSeconds': 20}),
    throwsFormatException,
  );
  await guard.execute(
    SensitiveOperation.supervision,
    () => guard.setEnabled(false),
    password: _testPassword,
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.text('内容过滤设置需要监管验证'));
  await _until(tester, () => find.byType(TextField).evaluate().isNotEmpty);
  await _enter(tester, find.byType(TextField), _testPassword);
  await _tap(tester, find.text('验证并继续'));
  await _until(tester, () => !access.protectContentFilter);
}

Future<void> _enter(WidgetTester tester, Finder field, String value) async {
  await tester.tap(field);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(field, value);
  await tester.pump(const Duration(milliseconds: 100));
  expect(
    tester.widget<TextField>(field).controller!.text == value,
    isTrue,
    reason: 'Native input must receive the replacement text',
  );
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    done(),
    isTrue,
    reason:
        'adultVerified=${_services.installationAccess.adultVerified}; '
        'configured=${_services.supervision.configured}; '
        'skip=${_services.settings.value.filterSkipSeconds}; '
        'dialogs=${find.byType(AlertDialog).evaluate().length}; '
        'wrong=${find.text("访问密码不正确").evaluate().isNotEmpty}; '
        'saveError=${find.text("验证状态保存失败，请重试").evaluate().isNotEmpty}; '
        'busy=${find.byType(LinearProgressIndicator).evaluate().isNotEmpty}',
  );
  await tester.pump(const Duration(milliseconds: 150));
}
