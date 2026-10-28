import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/product_app.dart';
import 'package:zero_player/app/shell.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import '../test_support/http_test_server.dart';

late AppServices services;
late Directory root;
late HttpTestServer fixture;
final boundary = GlobalKey();
const configuredProject = String.fromEnvironment('PROJECT_ROOT');
final project = configuredProject.isEmpty
    ? Directory.current.path
    : configuredProject;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(_setUp);
  testWidgets('hidden startup window remains visible after fullscreen exit', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await windowManager.hide();
    expect(await windowManager.isVisible(), isFalse);
    await services.platform.setAppFullscreen(true);
    await windowManager.show();
    await tester.pumpAndSettle();
    await services.platform.setAppFullscreen(false);
    final visible = await windowManager.isVisible();
    await windowManager.show();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(
      visible,
      isTrue,
      reason: 'Exiting fullscreen must not restore a hidden startup style',
    );
  });
  tearDown(() async {
    await services.platform.setAppFullscreen(false);
    await services.close();
    await fixture.close();
    await root.delete(recursive: true);
  });
  testWidgets(
    'startup fullscreen, onboarding, metadata and window recovery',
    (tester) async {
      await _mount(tester);
      await _waitWindow(tester, true);
      await _guide(tester);
      await _home(tester);
      await _windowTransitions(tester);
      await _menuAndDisclaimer(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await services.settings.load();
      expect(services.settings.value.navigationGuideSeen, isTrue);
      await services.settings.update({'startFullscreen': false});
      await _mount(tester);
      expect(find.text('从这里开始探索'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _setUp() async {
  root = await Directory.systemTemp.createTemp('zero-shell-regression-');
  services = AppServices.scoped(
    root,
    AppDatabase.memory(),
    allowPrivateNetworks: true,
  );
  await services.settings.load();
  await services.settings.update({
    'recommendation': 'off',
    'backgroundProbe': false,
  });
  await services.platform.initialize();
  await windowManager.unmaximize();
  await windowManager.setSize(const Size(1100, 760));
  await services.store.initialize();
  await services.gateway.start();
  fixture = await HttpTestServer.start((request) async {
    if (request.uri.path == '/poster.png') {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(
        await File('$project/test_support/generated/poster.png').readAsBytes(),
      );
      return;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'pagecount': 1,
        'class': [
          {'type_id': '1', 'type_name': '<b>电影</b>'},
        ],
        'list': List.generate(
          48,
          (i) => {
            'vod_id': '$i',
            'vod_name': '<em>侠</em><em>探</em>杰克 $i',
            'vod_pic': fixture.baseUri.resolve('poster.png').toString(),
            'vod_year': '2026',
            'vod_content': '<p>本地回归测试简介。</p><p>验证全屏和普通窗口。</p>',
            'vod_remarks': '&lt;b&gt;高清&lt;/b&gt;',
            'type_name': '电影',
          },
        ),
      }),
    );
  });
  final source = await services.sources.saveManual(
    '回归测试频道',
    fixture.baseUri.resolve('api'),
  );
  await services.settings.update({'homeChannel': source});
}

Future<void> _mount(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: RepaintBoundary(key: boundary, child: const ProductApp()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _guide(WidgetTester tester) async {
  expect(find.text('从这里开始探索'), findsOneWidget);
  await _screenshot('shell-navigation-guide.png');
  await tester.tap(find.text('阅读免责声明与版权说明'));
  await tester.pumpAndSettle();
  expect(find.text('免责声明与版权说明'), findsOneWidget);
  expect(find.textContaining('公开可访问不代表已获授权'), findsOneWidget);
  await _screenshot('shell-disclaimer.png');
  await tester.tap(find.text('关闭说明'));
  await tester.pumpAndSettle();
  expect(services.settings.value.navigationGuideSeen, isFalse);
  await tester.tap(find.text('我知道了，开始使用'));
  await tester.pumpAndSettle();
  expect(services.settings.value.navigationGuideSeen, isTrue);
  expect(find.text('从这里开始探索'), findsNothing);
}

Future<void> _home(WidgetTester tester) async {
  final search = find.byKey(const ValueKey('home-search'));
  expect(search.hitTestable(), findsOneWidget);
  expect(
    tester.getCenter(search).dy,
    closeTo(
      tester.getCenter(find.byType(DropdownButtonFormField<String>).first).dy,
      1,
    ),
  );
  expect(find.textContaining('<em>'), findsNothing);
  expect(find.textContaining('&lt;'), findsNothing);
  expect(find.text('侠探杰克 0'), findsWidgets);
  await _screenshot('shell-home-cinema.png');
  await services.settings.update({'theme': 'light'});
  await tester.pumpAndSettle();
  await _screenshot('shell-home-light.png');
  await services.settings.update({'theme': 'cinema'});
  await tester.tap(search);
  await tester.pumpAndSettle();
  expect(find.byType(TextField), findsOneWidget);
  await tester.sendKeyEvent(
    LogicalKeyboardKey.escape,
    physicalKey: PhysicalKeyboardKey.escape,
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
  expect(services.platform.appFullscreen.value, isTrue);
}

Future<void> _windowTransitions(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.tap(find.byTooltip('退出应用全屏 (F11)'));
    await _waitWindow(tester, false);
    expect(await windowManager.isFullScreen(), isFalse);
    expect(await windowManager.isVisible(), isTrue);
    final size = await windowManager.getSize();
    expect(size.width, closeTo(1100, 3));
    expect(size.height, closeTo(760, 3));
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(
      LogicalKeyboardKey.f11,
      physicalKey: PhysicalKeyboardKey.f11,
    );
    await _waitWindow(tester, true);
  }
  await tester.sendKeyEvent(
    LogicalKeyboardKey.escape,
    physicalKey: PhysicalKeyboardKey.escape,
  );
  await _waitWindow(tester, false);
  await _screenshot('shell-windowed.png');
  await Future.wait([
    services.platform.setAppFullscreen(true),
    services.platform.setAppFullscreen(true),
    services.platform.setAppFullscreen(false),
  ]);
  await _waitWindow(tester, false);
  await windowManager.maximize();
  await tester.pumpAndSettle();
  await services.platform.setAppFullscreen(true);
  await _waitWindow(tester, true);
  await tester.tap(find.byTooltip('退出应用全屏 (F11)'));
  await _waitWindow(tester, false);
  expect(await windowManager.isMaximized(), isTrue);
  await windowManager.unmaximize();
  await tester.pumpAndSettle();
}

Future<void> _menuAndDisclaimer(WidgetTester tester) async {
  final scroll = tester
      .widget<CustomScrollView>(find.byKey(const ValueKey('discovery-scroll')))
      .controller!;
  scroll.jumpTo(650);
  await tester.pumpAndSettle();
  await tester.tap(find.text('菜单').hitTestable());
  await tester.pumpAndSettle();
  expect(find.byTooltip('收起导航'), findsOneWidget);
  await tester.tap(find.byTooltip('收起导航'));
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.byType(AppShell))).go('/settings');
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('免责声明与版权说明'),
    500,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('免责声明与版权说明'));
  await tester.pumpAndSettle();
  expect(find.text('第三方渠道与版权反馈'), findsOneWidget);
  await tester.tap(find.text('关闭说明'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _waitWindow(WidgetTester tester, bool full) async {
  final clock = Stopwatch()..start();
  while (services.platform.appFullscreen.value != full ||
      services.platform.fullscreenChanging.value) {
    if (clock.elapsed > const Duration(seconds: 15)) {
      throw StateError('Native fullscreen transition did not complete');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> _screenshot(String name) async {
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
