import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/product_app.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/persistence/installation_metadata.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/sources/presentation/source_card.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import 'package:zero_player/features/settings/presentation/adult_filter_setting.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import '../test_support/http_test_server.dart';
import '../test_support/fixture_project.dart';

final project = fixtureProjectRoot();
const password = 'acceptance-password-only';
late AppServices services;
late Directory root;
late HttpTestServer fixture;
late String ordinaryId, adultId, forestId;
late IntegrationTestWidgetsFlutterBinding binding;
final boundary = GlobalKey();

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  setUp(_setup);
  tearDown(() async {
    await services.close();
    await fixture.close();
    await root.delete(recursive: true);
  });
  testWidgets(
    'supervision setup, per-operation gates, recovery and native stop',
    (tester) async {
      await binding.setSurfaceSize(const Size(1280, 850));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [servicesProvider.overrideWithValue(services)],
          child: RepaintBoundary(key: boundary, child: const ProductApp()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      debugPrint('SUPERVISION_STAGE mounted');
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go('/supervision');
      await tester.pump(const Duration(milliseconds: 350));
      final recovery = await _setupPassword(tester);
      debugPrint('SUPERVISION_STAGE credentials configured');
      await _homePolicyCheck(tester, router);
      router.go('/supervision');
      await tester.pump(const Duration(milliseconds: 350));
      await _rules(tester);
      debugPrint('SUPERVISION_STAGE rules saved');
      await _capture('supervision-settings-desktop.png');
      await binding.setSurfaceSize(const Size(390, 850));
      await tester.pump(const Duration(milliseconds: 350));
      await _capture('supervision-settings-mobile.png');
      expect(tester.takeException(), isNull);
      await binding.setSurfaceSize(const Size(1280, 850));
      await tester.pump(const Duration(milliseconds: 350));
      await _channelGate(tester, router);
      debugPrint('SUPERVISION_STAGE channel gate checked');
      router.go('/supervision');
      await tester.pump(const Duration(milliseconds: 350));
      await _recover(tester, recovery);
      await _nativePlayback();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 350));
      await binding.setSurfaceSize(null);
      expect(tester.takeException(), isNull);
      debugPrint(
        'SUPERVISION_ACCEPTANCE setup=yes singleOperation=yes recovery=yes nativeStop=yes',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _setup() async {
  debugPrint('SUPERVISION_STAGE fixture start');
  root = await Directory.systemTemp.createTemp('zero-supervision-acceptance-');
  services = AppServices.scoped(
    root,
    AppDatabase(File('${root.path}/test.sqlite')),
    allowPrivateNetworks: true,
  );
  await services.supervision.load();
  debugPrint('SUPERVISION_STAGE state loaded');
  await services.db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
    installationAccessKey,
    upgradedInstallationAccess,
  ]);
  await services.settings.load();
  await services.settings.update({
    'recommendation': 'off',
    'backgroundProbe': false,
    'startFullscreen': false,
    'navigationGuideSeen': true,
  });
  await services.platform.initialize();
  await services.store.initialize();
  await services.gateway.start();
  fixture = await HttpTestServer.start((request) async {
    if (request.uri.path == '/vod') {
      request.response.write(
        jsonEncode({
          'pagecount': 1,
          'class': [
            {'type_id': '1', 'type_name': '电影'},
            {'type_id': '9', 'type_name': '倫理'},
          ],
          'list': [
            {'vod_id': 'adult', 'vod_name': '受限测试条目', 'type_id': '9'},
          ],
        }),
      );
    } else {
      await serveLocalFile(
        request,
        File('$project/test_support/generated/sample.mp4'),
        contentType: 'video/mp4',
      );
    }
  });
  ordinaryId = await services.sources.saveManual(
    '安全演示源',
    fixture.baseUri.resolve('vod'),
  );
  adultId = await services.sources.saveManual(
    '鲨鱼',
    fixture.baseUri.resolve('adult'),
    classification: 'adult',
    enabled: false,
  );
  forestId = await services.sources.saveManual(
    '森林',
    Uri.parse('https://slapibf.com/api.php/provide/vod'),
  );
  await services.live.importText(
    '测试列表',
    fixture.baseUri.resolve('list'),
    '#EXTM3U\n#EXTINF:-1 group-title="新闻",新闻演示\n${fixture.baseUri.resolve('sample.mp4')}\n#EXTINF:-1 group-title="成人",受限演示\n${fixture.baseUri.resolve('sample.mp4')}',
  );
  debugPrint('SUPERVISION_STAGE fixture created');
  expect((await services.live.channels()).length, 1);
  await expectLater(
    services.detail(ordinaryId, 'adult'),
    throwsA(isA<ContentBlocked>()),
  );
}

Future<String> _setupPassword(WidgetTester tester) async {
  await tester.tap(find.text('首次设置密码和恢复码'));
  await tester.pump(const Duration(milliseconds: 350));
  await _newPassword(tester, password);
  await _until(tester, () => find.text('保存恢复码').evaluate().isNotEmpty);
  final code = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
  expect(
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '完成设置'))
        .onPressed,
    isNull,
  );
  await tester.tap(find.byType(Checkbox));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.text('完成设置'));
  await _until(tester, () => services.supervision.configured);
  await tester.pump(const Duration(milliseconds: 350));
  expect(services.supervision.enabled, isTrue);
  return code;
}

Future<void> _homePolicyCheck(WidgetTester tester, GoRouter router) async {
  await services.supervision.execute(
    SensitiveOperation.supervision,
    () => services.supervision.setEnabled(false),
    password: password,
  );
  await services.settings.update({'filterAdult': false});
  await services.sources.setEnabled(adultId, true);
  await services.supervision.execute(
    SensitiveOperation.supervision,
    () => services.supervision.setEnabled(true),
    password: password,
  );
  expect(services.settings.value.filterAdult, isFalse);
  expect(services.contentPolicy.filterAdult, isTrue);
  router.go('/');
  await tester.pump(const Duration(milliseconds: 350));
  await _until(
    tester,
    () => find.byType(DropdownButton<String>).evaluate().isNotEmpty,
  );
  await tester.pump(const Duration(milliseconds: 350));
  final choices = tester
      .widget<DropdownButton<String>>(find.byType(DropdownButton<String>).first)
      .items!
      .map((e) => e.value)
      .toList();
  expect(choices, contains(ordinaryId));
  expect(choices, isNot(contains(adultId)));
  expect(choices, isNot(contains(forestId)));
  await _capture('supervision-home-filtered-0.0.5.png');
  router.go('/settings');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.scrollUntilVisible(
    find.byType(AdultFilterSetting),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  final toggle = tester.widget<SwitchListTile>(
    find.descendant(
      of: find.byType(AdultFilterSetting),
      matching: find.byType(SwitchListTile),
    ),
  );
  expect(toggle.value, isTrue);
  expect(toggle.onChanged, isNull);
  await services.sources.setEnabled(adultId, false);
  debugPrint(
    'SUPERVISION_HOME verified=forest,shark preference=false mandatory=true',
  );
}

Future<void> _newPassword(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField).at(0), value);
  await tester.enterText(find.byType(TextField).at(1), value);
  await tester.tap(find.text('生成恢复码'));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _authenticate(WidgetTester tester, String secret) async {
  await _until(tester, () => find.text('验证并继续').evaluate().isNotEmpty);
  await tester.enterText(find.byType(TextField).last, secret);
  await tester.tap(find.text('验证并继续'));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _rules(WidgetTester tester) async {
  await tester.ensureVisible(find.byTooltip('添加屏蔽关键词'));
  await tester.tap(find.byTooltip('添加屏蔽关键词'));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.enterText(find.byType(TextField), '演示关键词');
  await tester.tap(find.text('保存'));
  await tester.pump(const Duration(milliseconds: 400));
  await _authenticate(tester, password);
  await _until(tester, () => services.supervision.rules.keywords.isNotEmpty);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.byTooltip('添加屏蔽频道'));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.text('安全演示源'));
  await tester.pump(const Duration(milliseconds: 350));
  await _authenticate(tester, password);
  await _until(tester, () => services.supervision.rules.channels.isNotEmpty);
  await tester.pump(const Duration(milliseconds: 350));
  expect(services.contentPolicy.sourceIdAllowed(ordinaryId), isFalse);
}

Future<void> _channelGate(WidgetTester tester, GoRouter router) async {
  router.go('/sources');
  await tester.pump(const Duration(milliseconds: 350));
  final card = find.byWidgetPredicate(
    (w) => w is SourceCard && w.source.id == adultId,
  );
  final toggle = find.descendant(of: card, matching: find.byType(Switch));
  await _until(tester, () => card.evaluate().isNotEmpty);
  await tester.ensureVisible(toggle);
  await tester.tap(find.descendant(of: card, matching: find.text('详情')));
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.text('禁止访问'), findsOneWidget);
  expect(find.textContaining('监管设置人已禁止访问'), findsOneWidget);
  expect(find.text('接口网址'), findsNothing);
  expect(find.text('网站主页'), findsNothing);
  expect(find.byType(SelectableText), findsNothing);
  await _capture('supervision-blocked-source-0.0.5.png');
  await tester.tap(find.text('关闭'));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(toggle);
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.text('验证监管密码'), findsOneWidget);
  await _capture('supervision-channel-gate.png');
  await tester.tap(find.text('取消'));
  await tester.pump(const Duration(milliseconds: 350));
  expect((await services.sources.find(adultId))!.enabled, isFalse);
  await tester.tap(toggle);
  await tester.pump(const Duration(milliseconds: 350));
  await _authenticate(tester, password);
  await _untilAsync(
    tester,
    () async => (await services.sources.find(adultId))!.enabled,
  );
  await tester.pump(const Duration(milliseconds: 350));
  await services.sources.setEnabled(adultId, false);
  await expectLater(
    services.sources.setEnabled(adultId, true),
    throwsFormatException,
  );
  await expectLater(
    services.settings.update({'filterAdult': false}),
    throwsFormatException,
  );
}

Future<void> _recover(WidgetTester tester, String code) async {
  await tester.tap(find.text('忘记密码：使用恢复码重设'));
  await tester.pump(const Duration(milliseconds: 350));
  await _newPassword(tester, 'replacement-acceptance-password');
  await _authenticate(tester, code);
  await _until(tester, () => find.text('保存恢复码').evaluate().isNotEmpty);
  final newCode = tester
      .widget<SelectableText>(find.byType(SelectableText))
      .data!;
  expect(newCode != code, isTrue);
  await tester.tap(find.byType(Checkbox));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.text('完成设置'));
  await tester.pump(const Duration(milliseconds: 350));
  await _until(
    tester,
    () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
  );
  expect(services.supervision.rules.keywords, ['演示关键词']);
  expect(services.supervision.rules.channels.length, 1);
  await expectLater(
    services.supervision.execute(
      SensitiveOperation.supervision,
      () async {},
      password: code,
      useRecovery: true,
    ),
    throwsFormatException,
  );
  await expectLater(
    services.supervision.execute(
      SensitiveOperation.channels,
      () async {},
      password: password,
    ),
    throwsFormatException,
  );
}

Future<void> _nativePlayback() async {
  final channel = (await services.live.channels()).single;
  final engine = MediaKitEngine(gateway: services.gateway, videoOutput: false);
  final player = PlaybackController(services, engine);
  try {
    await player.open(
      PlaybackRequest(
        CatalogItem(
          sourceId: 'live',
          id: channel.id,
          title: '直播',
          lines: [
            PlayLine(channel.name, [Episode('1', channel.urls.single)]),
          ],
        ),
        live: true,
      ),
    );
    final watch = Stopwatch()..start();
    while (!engine.snapshot.playing &&
        watch.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(engine.snapshot.playing, isTrue);
    await services.supervision.execute(
      SensitiveOperation.supervision,
      () => services.supervision.updateRules(
        SupervisionRules(
          channels: services.supervision.rules.channels,
          keywords: [...services.supervision.rules.keywords, channel.name],
        ),
      ),
      password: 'replacement-acceptance-password',
    );
    final stopping = Stopwatch()..start();
    while (engine.snapshot.playing &&
        stopping.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('SUPERVISION_NATIVE stopMs=${stopping.elapsedMilliseconds}');
    expect(player.blocked, isTrue);
    expect(engine.snapshot.playing, isFalse);
    expect(
      await (engine.player.platform as NativePlayer).getProperty('idle-active'),
      'yes',
    );
    await player.toggle();
    expect(engine.snapshot.playing, isFalse);
  } finally {
    await player.close();
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed > const Duration(seconds: 20)) {
      throw StateError('Expected UI state timed out');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _untilAsync(
  WidgetTester tester,
  Future<bool> Function() ready,
) async {
  final clock = Stopwatch()..start();
  while (!await ready()) {
    if (clock.elapsed > const Duration(seconds: 20)) {
      throw StateError('Expected data state timed out');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _capture(String name) async {
  final image =
      await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$project/artifacts/$name',
    ).writeAsBytes(data!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
