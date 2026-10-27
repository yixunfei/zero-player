import 'dart:convert';
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
import 'package:zero_player/core/persistence/app_database.dart';
import '../test_support/http_test_server.dart';

const configuredProject = String.fromEnvironment('PROJECT_ROOT');
final project = configuredProject.isEmpty
    ? Directory.current.path
    : configuredProject;
late IntegrationTestWidgetsFlutterBinding binding;
late AppServices services;
late Directory root;
late HttpTestServer fixture;
late String sourceId;
final requests = <String>[];
final boundary = GlobalKey();

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  setUp(_setUp);
  tearDown(() async {
    await services.close();
    await fixture.close();
    await root.delete(recursive: true);
  });
  testWidgets(
    'home covers pagination aggregation persistence refresh and disposal',
    (tester) async {
      await _mount(tester);
      await _interactionExperience(tester);
      await _returnTopAndFonts(tester);
      await _pagination(tester);
      await _categoryRefresh(tester);
      await _aggregateAndSave(tester);
      await _settingsAndFallback(tester);
      await tester.pumpWidget(const SizedBox());
      await binding.setSurfaceSize(null);
      await tester.pumpAndSettle();
      expect(services.posters.pendingCount, 0);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  if (const bool.fromEnvironment('PUBLIC_HOME_SMOKE')) {
    testWidgets(
      'public Douban covers decode and render on Windows',
      _publicCovers,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

Future<void> _setUp() async {
  requests.clear();
  root = await Directory.systemTemp.createTemp('zero-home-test-');
  services = AppServices.scoped(root, AppDatabase.memory());
  await services.settings.load();
  await services.settings.update({
    'recommendation': 'off',
    'backgroundProbe': false,
    'navigationGuideSeen': true,
    'startFullscreen': false,
  });
  await services.platform.initialize();
  await services.store.initialize();
  await services.gateway.start();
  fixture = await HttpTestServer.start(_serve);
  sourceId = await services.sources.saveManual(
    '首页测试频道',
    fixture.baseUri.resolve('api'),
  );
  await services.settings.update({'homeChannel': sourceId});
}

Future<void> _serve(HttpRequest request) async {
  if (request.uri.path == '/poster.png') {
    request.response.headers.contentType = ContentType('image', 'png');
    request.response.add(
      await File('$project/test_support/generated/poster.png').readAsBytes(),
    );
    return;
  }
  final page = int.tryParse(request.uri.queryParameters['pg'] ?? '') ?? 1;
  final category = request.uri.queryParameters['t'] ?? '';
  requests.add('$category:$page');
  request.response.headers.contentType = ContentType.json;
  request.response.write(
    jsonEncode({
      'pagecount': 3,
      'class': [
        {'type_id': '1', 'type_name': '电影'},
        {'type_id': '2', 'type_name': '美剧'},
        {'type_id': '3', 'type_name': 'AI剧场'},
      ],
      'list': List.generate(
        12,
        (i) => {
          'vod_id': '$category-$page-$i',
          'vod_name': '本地影片$category-$page-$i',
          'vod_pic': '${fixture.baseUri}poster.png',
          'vod_year': '2026',
          'type_name': '电影',
          'vod_remarks': '高清',
        },
      ),
    }),
  );
}

Future<void> _mount(WidgetTester tester) async {
  await binding.setSurfaceSize(const Size(1280, 900));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: RepaintBoundary(key: boundary, child: const ProductApp()),
    ),
  );
  await _until(tester, () => find.text('AI剧场').evaluate().isNotEmpty);
  await _until(
    tester,
    () => tester
        .widgetList<RawImage>(find.byType(RawImage))
        .any((image) => image.image != null),
  );
  expect(find.text('首页测试频道'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

ScrollController _scroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.byKey(const ValueKey('discovery-scroll')))
    .controller!;

Future<void> _interactionExperience(WidgetTester tester) async {
  expect(find.byType(NavigationRail), findsNothing);
  await tester.tap(find.byTooltip('展开导航 (Ctrl+M)'));
  await tester.pumpAndSettle();
  expect(find.text('收起导航'), findsNothing);
  expect(find.byTooltip('收起导航'), findsOneWidget);
  await _screenshot('experience-navigation-desktop.png');
  await tester.tap(find.byTooltip('收起导航'));
  await tester.pumpAndSettle();
  await services.platform.setAppFullscreen(true);
  await tester.pumpAndSettle();
  expect(find.byType(AppBar), findsOneWidget);
  expect(
    tester.getBottomLeft(find.byType(AppBar)).dy,
    lessThanOrEqualTo(tester.getTopLeft(find.text('你的私人影院')).dy),
  );
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  expect(find.byTooltip('收起导航'), findsOneWidget);
  await tester.tap(find.byTooltip('收起导航'));
  await services.platform.setAppFullscreen(false);
  await tester.pumpAndSettle();
  await binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpAndSettle();
  _scroll(tester).jumpTo(400);
  await tester.pumpAndSettle();
  final info = find.byTooltip('展开节目简介').hitTestable().first;
  await tester.tap(info);
  await tester.pumpAndSettle();
  expect(find.byTooltip('收起节目简介'), findsOneWidget);
  await _screenshot('experience-poster-phone.png');
  await tester.tap(find.byTooltip('收起节目简介'));
  await tester.pumpAndSettle();
  expect(find.byTooltip('收起节目简介'), findsNothing);
  expect(tester.takeException(), isNull);
  _scroll(tester).jumpTo(0);
  await binding.setSurfaceSize(const Size(1024, 768));
  await tester.pumpAndSettle();
  await _screenshot('experience-tablet.png');
  expect(tester.takeException(), isNull);
  await binding.setSurfaceSize(const Size(1920, 1080));
  await services.settings.update({'mode': 'television'});
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
  await tester.pumpAndSettle();
  expect(find.byTooltip('收起导航'), findsOneWidget);
  await _screenshot('experience-tv-menu.png');
  await tester.tap(find.byTooltip('收起导航'));
  await services.settings.update({'mode': 'auto'});
  await binding.setSurfaceSize(const Size(1280, 900));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _returnTopAndFonts(WidgetTester tester) async {
  expect(services.settings.value.font, 'xiaolai');
  final theme = Theme.of(tester.element(find.byType(AppShell)));
  expect(theme.textTheme.bodyMedium!.fontFamily, 'Xiaolai');
  await services.settings.update({'theme': 'light'});
  await tester.pumpAndSettle();
  await _screenshot('refinement-home-light.png');
  _scroll(tester).jumpTo(650);
  await tester.pumpAndSettle();
  expect(find.byTooltip('返回顶部 (Ctrl+Home)'), findsOneWidget);
  expect(find.byTooltip('展开导航 (Ctrl+M)').hitTestable(), findsNothing);
  await _screenshot('refinement-return-top.png');
  await tester.drag(
    find.byKey(const ValueKey('discovery-scroll')),
    const Offset(0, 80),
  );
  await tester.pumpAndSettle();
  expect(find.byTooltip('展开导航 (Ctrl+M)').hitTestable(), findsOneWidget);
  expect(find.byTooltip('刷新推荐').hitTestable(), findsOneWidget);
  await tester.tap(find.byTooltip('返回顶部 (Ctrl+Home)'));
  await tester.pumpAndSettle();
  expect(_scroll(tester).offset, 0);
  _scroll(tester).jumpTo(650);
  await tester.pumpAndSettle();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.home);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  expect(_scroll(tester).offset, 0);
  await services.settings.update({'font': 'system'});
  await tester.pumpAndSettle();
  expect(
    Theme.of(
      tester.element(find.byType(AppShell)),
    ).textTheme.bodyMedium!.fontFamily,
    isNot('Xiaolai'),
  );
  await services.settings.update({'font': 'xiaolai', 'theme': 'cinema'});
  await tester.pumpAndSettle();
}

Future<void> _pagination(WidgetTester tester) async {
  await _screenshot('home-local-posters.png');
  expect(requests.where((r) => r == ':1').length, 1);
  _scroll(tester).jumpTo(_scroll(tester).position.maxScrollExtent);
  await _until(tester, () => requests.contains(':2'));
  await tester.pump(const Duration(milliseconds: 300));
  _scroll(tester).jumpTo(_scroll(tester).position.maxScrollExtent);
  await _until(tester, () => requests.contains(':3'));
  await _until(
    tester,
    () => tester
        .widgetList<SliverGrid>(find.byType(SliverGrid))
        .any((grid) => grid.delegate.estimatedChildCount == 36),
  );
  _scroll(tester).jumpTo(_scroll(tester).position.maxScrollExtent);
  await tester.pumpAndSettle();
  expect(find.text('已展示全部 36 部'), findsOneWidget);
  expect(requests.where((r) => r == ':2').length, 1);
  expect(requests.where((r) => r == ':3').length, 1);
  final count = requests.length;
  _scroll(tester).jumpTo(_scroll(tester).position.maxScrollExtent);
  await tester.pump(const Duration(milliseconds: 200));
  expect(requests.length, count);
  _scroll(tester).jumpTo(0);
  await tester.pumpAndSettle();
  final before = requests.where((r) => r == ':1').length;
  await tester.drag(
    find.byKey(const ValueKey('discovery-scroll')),
    const Offset(0, 500),
  );
  await _until(tester, () => requests.where((r) => r == ':1').length > before);
  await tester.pumpAndSettle();
}

Future<void> _categoryRefresh(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ChoiceChip, '美剧'));
  await _until(tester, () => requests.contains('2:1'));
  await tester.pumpAndSettle();
  final count = requests.where((r) => r == '2:1').length;
  await tester.tap(find.byTooltip('刷新推荐'));
  await _until(tester, () => requests.where((r) => r == '2:1').length > count);
  await tester.pumpAndSettle();
  expect(
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '美剧')).selected,
    isTrue,
  );
}

Future<void> _aggregateAndSave(WidgetTester tester) async {
  await tester.tap(find.text('分类聚合'));
  await tester.pumpAndSettle();
  await _until(
    tester,
    () => requests.contains('1:1') && requests.contains('2:1'),
  );
  await tester.tap(find.byTooltip('设为开屏默认'));
  await tester.pumpAndSettle();
  expect(services.settings.value.homeLayout, 'aggregate');
  expect(services.settings.value.homeChannel, sourceId);
  await _screenshot('home-aggregate-desktop.png');
  final router = GoRouter.of(tester.element(find.byType(AppShell)));
  router.go('/history');
  await tester.pumpAndSettle();
  router.go('/');
  await _until(tester, () => find.byTooltip('当前开屏默认').evaluate().isNotEmpty);
  expect(
    tester
        .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
        .selected,
    {true},
  );
  await binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await _screenshot('home-aggregate-phone.png');
  await binding.setSurfaceSize(const Size(1280, 900));
  await tester.pumpAndSettle();
}

Future<void> _settingsAndFallback(WidgetTester tester) async {
  final router = GoRouter.of(tester.element(find.byType(AppShell)));
  router.go('/settings');
  await tester.pumpAndSettle();
  expect(find.text('默认开屏频道'), findsOneWidget);
  expect(find.text('开屏使用分类聚合'), findsOneWidget);
  await services.sources.setEnabled(sourceId, false);
  router.go('/');
  await _until(
    tester,
    () => find.textContaining('默认频道已移除').evaluate().isNotEmpty,
  );
  expect(find.text('推荐已关闭'), findsWidgets);
  // The user's preference is retained for later re-enabling the source.
  expect(services.settings.value.homeChannel, sourceId);
  expect(tester.takeException(), isNull);
}

Future<void> _publicCovers(WidgetTester tester) async {
  await services.settings.update({
    'recommendation': 'douban',
    'homeChannel': '',
  });
  final recommendations = await services.recommendations.load('douban');
  final results = <Map<String, Object?>>[];
  for (final item in recommendations.items.take(8)) {
    final lease = services.posters.acquire(item.poster);
    try {
      final codec = await ui.instantiateImageCodec(
        await lease.bytes,
        targetWidth: 160,
      );
      try {
        final frame = await codec.getNextFrame();
        results.add({
          'title': item.title,
          'width': frame.image.width,
          'height': frame.image.height,
        });
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } catch (error) {
      results.add({'title': item.title, 'error': '$error'});
    } finally {
      lease.release();
    }
  }
  await File(
    '$project/artifacts/home-public-decode.json',
  ).writeAsString(jsonEncode(results));
  expect(results.where((r) => !r.containsKey('error')).length, greaterThan(0));
  await binding.setSurfaceSize(const Size(1280, 900));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: RepaintBoundary(key: boundary, child: const ProductApp()),
    ),
  );
  await _until(
    tester,
    () =>
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .where((i) => i.image != null)
            .length >=
        3,
  );
  await tester.pump(const Duration(seconds: 2));
  await _screenshot('home-public-douban.png');
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await binding.setSurfaceSize(null);
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > const Duration(seconds: 30)) {
      throw StateError(
        'Homepage state timed out; requests=$requests; '
        'text=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
      );
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
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$project/artifacts/$name',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
