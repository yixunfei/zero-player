import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/product_app.dart';
import 'package:zero_player/app/shell.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/presentation/live_browser.dart';
import 'package:zero_player/features/live/presentation/live_page.dart';
import 'package:zero_player/features/search/presentation/search_page.dart';
import 'package:zero_player/features/settings/presentation/settings_page.dart';
import 'package:zero_player/features/playback/presentation/player_page.dart';
import '../test_support/http_test_server.dart';

const configuredProject = String.fromEnvironment('PROJECT_ROOT');
final project = configuredProject.isEmpty
    ? Directory.current.path
    : configuredProject;
late IntegrationTestWidgetsFlutterBinding binding;
late AppServices services;
late HttpTestServer fixture;
late Directory root;
final boundary = GlobalKey();

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  setUp(_setUp);
  tearDown(() async {
    await services.platform.setAppFullscreen(false);
    await services.close();
    await fixture.close();
    await root.delete(recursive: true);
  });
  testWidgets(
    'TV guide, health choices, responsive layouts and search navigation',
    (tester) async {
      await _mount(tester);
      await _liveManagement(tester);
      await _subscriptionManagement(tester);
      await _liveKeysAndLayouts(tester);
      await _explicitPlayback(tester);
      await _searchNavigation(tester);
      await _appearanceSettings(tester);
      await tester.pumpWidget(const SizedBox());
      await binding.setSurfaceSize(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _setUp() async {
  root = await Directory.systemTemp.createTemp('zero-interaction-test-');
  services = AppServices.scoped(root, AppDatabase.memory());
  await services.settings.load();
  await services.settings.update({
    'recommendation': 'off',
    'backgroundProbe': false,
    'navigationGuideSeen': true,
  });
  await services.platform.initialize();
  await services.store.initialize();
  await services.gateway.start();
  fixture = await HttpTestServer.start((request) async {
    await serveLocalFile(
      request,
      File('$project/test_support/generated/sample.mp4'),
      contentType: 'video/mp4',
    );
  });
  await services.live.importText(
    '本地电视验证',
    fixture.baseUri.resolve('list.m3u'),
    '#EXTM3U\n${List.generate(18, (i) => '#EXTINF:-1 group-title="央视",CCTV-${i + 1}\n${fixture.baseUri}sample.mp4\n').join()}'
        '#EXTINF:-1 group-title="卫视",浙江卫视\n${fixture.baseUri}sample.mp4\n',
  );
}

GoRouter _router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(AppShell)));

Future<void> _mount(WidgetTester tester) async {
  await binding.setSurfaceSize(const Size(1280, 800));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: RepaintBoundary(key: boundary, child: const ProductApp()),
    ),
  );
  await tester.pumpAndSettle();
  _router(tester).go('/live');
  await _until(tester, () => find.byType(LiveBrowser).evaluate().isNotEmpty);
  await tester.pumpAndSettle();
  expect(tester.widget<LiveBrowser>(find.byType(LiveBrowser)).group, '央视');
  expect(find.text('CCTV-1'), findsNWidgets(2));
  expect(find.byType(PlayerPage), findsNothing);
  expect(
    fixture.calls['/sample.mp4'],
    isNull,
    reason: 'selection must not autoplay',
  );
  await _screenshot('interaction-live-desktop.png');
}

Future<void> _liveManagement(WidgetTester tester) async {
  await tester.tap(find.text('检测线路'));
  await _until(
    tester,
    () => find.textContaining('有媒体响应').evaluate().isNotEmpty,
  );
  await tester.tap(find.text('停止 / 关闭'));
  await tester.pumpAndSettle();
  final channel = (await services.live.channels()).first;
  expect(channel.health.latencyMs, isNotNull);
  await tester.tap(find.text('收藏频道'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('停用频道'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '确认'));
  await tester.pumpAndSettle();
  expect((await services.live.channels()).first.health.enabled, isFalse);
  await tester.tap(find.widgetWithText(ListTile, '已停用'));
  await tester.pumpAndSettle();
  expect(find.text('CCTV-1'), findsNWidgets(2));
  expect(find.text('播放频道'), findsOneWidget);
  expect(
    tester
        .widget<ButtonStyleButton>(
          find
              .ancestor(
                of: find.text('播放频道'),
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
              )
              .first,
        )
        .onPressed,
    isNull,
  );
  await _screenshot('interaction-live-disabled.png');
  await tester.tap(find.text('重新启用'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, '央视'));
  await tester.pumpAndSettle();
  expect((await services.live.channels()).first.health.enabled, isTrue);
  expect((await services.live.channels()).first.favorite, isTrue);
}

Future<void> _liveKeysAndLayouts(WidgetTester tester) async {
  final firstChannel = (await services.live.channels()).first;
  tester
      .widget<InkWell>(find.byKey(ValueKey('live-focus-${firstChannel.id}')))
      .focusNode!
      .requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pumpAndSettle();
  final cctv2 = (await services.live.channels()).firstWhere(
    (c) => c.name == 'CCTV-2',
  );
  expect(
    tester.widget<LiveBrowser>(find.byType(LiveBrowser)).selectedId,
    cctv2.id,
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final scroll = tester
      .widget<LiveBrowser>(find.byType(LiveBrowser))
      .controller;
  await tester.sendKeyEvent(LogicalKeyboardKey.end);
  await tester.pumpAndSettle();
  expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
  await tester.sendKeyEvent(LogicalKeyboardKey.home);
  await tester.pumpAndSettle();
  expect(scroll.offset, 0);
  await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
  await tester.pumpAndSettle();
  expect(scroll.offset, greaterThan(0));
  final input = find.descendant(
    of: find.byType(LivePage),
    matching: find.byType(TextField),
  );
  await tester.enterText(input, 'CCTV');
  await tester.pumpAndSettle();
  final before = scroll.offset;
  await tester.sendKeyEvent(LogicalKeyboardKey.home);
  await tester.pumpAndSettle();
  expect(
    scroll.offset,
    before,
    reason: 'Home in the search editor must not scroll the page',
  );
  await tester.tap(find.byTooltip('清空频道搜索'));
  FocusManager.instance.primaryFocus?.unfocus();
  scroll.jumpTo(0);
  for (final size in [
    const Size(390, 844),
    const Size(800, 1024),
    const Size(1920, 1080),
  ]) {
    await binding.setSurfaceSize(size);
    await services.settings.update({
      'mode': size.width > 1600 ? 'television' : 'auto',
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _screenshot('interaction-live-${size.width.toInt()}.png');
  }
  await services.settings.update({'mode': 'auto', 'theme': 'light'});
  await binding.setSurfaceSize(const Size(1280, 800));
  await tester.pumpAndSettle();
  await _screenshot('interaction-live-light.png');
}

Future<void> _subscriptionManagement(WidgetTester tester) async {
  await binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('直播管理'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('管理订阅 / EPG'));
  await tester.pumpAndSettle();
  final toggle = find.widgetWithText(SwitchListTile, '本地电视验证');
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  expect((await services.live.lists()).single['enabled'], 0);
  expect(await services.live.channels(), isEmpty);
  await _screenshot('interaction-live-subscriptions-phone.png');
  expect(tester.takeException(), isNull);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  expect((await services.live.lists()).single['enabled'], 1);
  await tester.tap(find.text('关闭'));
  await binding.setSurfaceSize(const Size(1280, 800));
  await tester.pumpAndSettle();
}

Future<void> _explicitPlayback(WidgetTester tester) async {
  final before = fixture.calls['/sample.mp4'] ?? 0;
  await tester.tap(find.text('播放频道'));
  await _until(tester, () => find.byType(PlayerPage).evaluate().isNotEmpty);
  final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
  expect(player.request.live, isTrue);
  expect(player.request.item.lines[player.request.line].name, 'CCTV-1');
  await _until(tester, () => (fixture.calls['/sample.mp4'] ?? 0) > before);
  GoRouter.of(tester.element(find.byType(PlayerPage))).pop();
  await tester.pumpAndSettle();
  expect((await services.live.channels()).first.recent, isTrue);
}

Future<void> _searchNavigation(WidgetTester tester) async {
  final router = _router(tester);
  router.go('/');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('home-search')));
  await tester.pumpAndSettle();
  expect(find.byType(SearchPage), findsOneWidget);
  await tester.enterText(find.byType(TextField), '电影');
  await tester.tap(find.byTooltip('清空输入'));
  await tester.pumpAndSettle();
  expect(
    tester.widget<TextField>(find.byType(TextField)).controller!.text,
    isEmpty,
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.byType(SearchPage), findsNothing);
  router.go('/search');
  await tester.pumpAndSettle();
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(
    find.byType(SearchPage),
    findsNothing,
    reason: 'system back from menu search returns home',
  );
  await _screenshot('interaction-home-contrast.png');
}

Future<void> _appearanceSettings(WidgetTester tester) async {
  _router(tester).go('/settings');
  await tester.pumpAndSettle();
  for (final entry in {
    'notoSans': 'NotoSansSC',
    'notoSerif': 'NotoSerifSC',
    'xiaolai': 'Xiaolai',
  }.entries) {
    await services.settings.update({'font': entry.key});
    await tester.pumpAndSettle();
    expect(
      Theme.of(
        tester.element(find.byType(SettingsPage)),
      ).textTheme.bodyMedium!.fontFamily,
      entry.value,
    );
    await _screenshot('interaction-font-${entry.key}.png');
  }
  expect(find.text('启动时沉浸全屏'), findsOneWidget);
  await tester.tap(find.widgetWithText(SwitchListTile, '启动时沉浸全屏'));
  await tester.pumpAndSettle();
  expect(services.settings.value.startFullscreen, isFalse);
  await services.platform.setAppFullscreen(true);
  await tester.pumpAndSettle();
  expect(services.platform.appFullscreen.value, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.f11);
  await _until(tester, () => !services.platform.appFullscreen.value);
  await tester.pumpAndSettle();
  expect(services.platform.appFullscreen.value, isFalse);
  final list = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(SettingsPage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.end);
  await tester.pumpAndSettle();
  expect(list.position.pixels, closeTo(list.position.maxScrollExtent, 1));
  await tester.sendKeyEvent(LogicalKeyboardKey.home);
  await tester.pumpAndSettle();
  expect(list.position.pixels, 0);
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  final clock = Stopwatch()..start();
  while (!predicate()) {
    if (clock.elapsed > const Duration(seconds: 20)) {
      throw StateError('UI did not reach expected state');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
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
