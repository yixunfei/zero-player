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
import 'package:path_provider/path_provider.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/product_app.dart';
import 'package:zero_player/app/poster_card.dart';
import 'package:zero_player/app/shell.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/presentation/source_choices_dialog.dart';
import 'package:zero_player/features/search/presentation/search_status_panel.dart';
import '../test_support/fake_player_engine.dart';
import '../test_support/http_test_server.dart';

late AppServices services;
late Directory root;
late HttpTestServer server;
late Directory screenshots;
final boundary = GlobalKey();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(_prepare);
  tearDown(() async {
    await services.platform.fullscreen(false);
    await services.close();
    await server.close();
    await root.delete(recursive: true);
  });
  testWidgets(
    'Android real fonts, search, source picker and system UI',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [servicesProvider.overrideWithValue(services)],
          child: RepaintBoundary(key: boundary, child: const ProductApp()),
        ),
      );
      await tester.pumpAndSettle();
      expect(services.platform.appFullscreen.value, isFalse);
      expect(find.byType(NavigationBar), findsOneWidget);
      await _searchAndChoose(tester);
      await services.platform.fullscreen(true);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.view.physicalSize.width,
        greaterThan(tester.view.physicalSize.height),
      );
      await _capture('player-fullscreen-landscape');
      await services.platform.fullscreen(false);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(services.platform.appFullscreen.value, isFalse);
      expect(find.byType(NavigationBar), findsOneWidget);
      for (var i = 0; i < 100 && tester.view.viewPadding.bottom == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _capture('restored-phone-navigation');
      final insets = tester.view.viewPadding;
      expect(insets.bottom, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: !Platform.isAndroid,
  );
}

Future<void> _prepare() async {
  root = await Directory.systemTemp.createTemp('zero-mobile-native-');
  final support = (await getApplicationSupportDirectory()).path;
  screenshots = Directory('$support/mobile-ui-results');
  await screenshots.create(recursive: true);
  services = AppServices.scoped(
    root,
    AppDatabase.memory(),
    allowPrivateNetworks: true,
    radioEngine: FakePlayerEngine.new,
  );
  await services.supervision.load();
  await services.settings.load();
  await services.settings.update({
    'recommendation': 'off',
    'navigationGuideSeen': true,
    'backgroundProbe': false,
    'startFullscreen': true,
  });
  await services.platform.initialize();
  server = await HttpTestServer.start((request) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'pagecount': 1,
        'class': [
          {'type_id': '1', 'type_name': '电视剧'},
        ],
        'list': List.generate(
          30,
          (i) => {
            'vod_id': '$i',
            'vod_name': '海军罪案调查处：溯源第三季 - 第 $i 部',
            'vod_year': '2026',
            'vod_remarks': '更新至04集 · 超长版本说明',
            'vod_content': '本地回归数据，用于核对手机窄屏下的真实字体与长标题显示。',
          },
        ),
      }),
    );
  });
  for (var i = 0; i < 3; i++) {
    await services.sources.saveManual(
      '超长资源频道名称 第 $i 个频道资源地址',
      server.baseUri.resolve('api/$i'),
    );
  }
}

Future<void> _searchAndChoose(WidgetTester tester) async {
  final router = GoRouter.of(tester.element(find.byType(AppShell)));
  router.go('/search');
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '海军罪案调查处');
  await tester.tap(find.byTooltip('搜索'));
  final controller = tester
      .widget<SearchStatusPanel>(find.byType(SearchStatusPanel))
      .controller;
  for (var i = 0; i < 150 && controller.loading; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(controller.loading, isFalse);
  expect(controller.items.length, 90);
  await tester.pumpAndSettle();
  await _capture('search-long-titles');
  final poster = find.byWidgetPredicate(
    (widget) => widget is PosterCard && widget.title.contains('第 0 部'),
  );
  await tester.ensureVisible(poster);
  await tester.tap(poster);
  await tester.pumpAndSettle();
  expect(find.byType(SourceChoicesDialog), findsOneWidget);
  expect(find.text('取消').hitTestable(), findsOneWidget);
  await _capture('source-picker-long-titles');
  expect(tester.takeException(), isNull);
  await tester.tap(find.text('取消'));
  await tester.pumpAndSettle();
  expect(find.byType(SourceChoicesDialog), findsNothing);
  expect(router.state.uri.path, '/search');
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await tester.pumpAndSettle();
}

Future<void> _capture(String name) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await render.toImage(pixelRatio: 1.5);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final output = screenshots.path;
    await File('$output/$name.png').writeAsBytes(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
