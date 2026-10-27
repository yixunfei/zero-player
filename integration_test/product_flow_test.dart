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
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/product_app.dart';
import 'package:zero_player/app/shell.dart';
import 'package:zero_player/app/poster_card.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/downloads/application/hls_download.dart';
import 'package:zero_player/media/export/media_exporter.dart';
import '../test_support/http_test_server.dart';

const configuredProject = String.fromEnvironment('PROJECT_ROOT');
final project = configuredProject.isEmpty
    ? Directory.current.path
    : configuredProject;

late Directory root;
late AppServices services;
late HttpTestServer fixture;
late IntegrationTestWidgetsFlutterBinding binding;

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('zero-product-test-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.settings.load();
    await services.settings.update({
      'navigationGuideSeen': true,
      'startFullscreen': false,
      'recommendation': 'off',
      'autoplay': false,
      'backgroundProbe': false,
    });
    await services.platform.initialize();
    await services.store.initialize();
    await services.gateway.start();
    fixture = await HttpTestServer.start((request) async {
      if (request.uri.path == '/api') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'pagecount': 1,
            'class': [
              {'type_id': '1', 'type_name': '电影'},
              {'type_id': '2', 'type_name': 'AI剧场'},
            ],
            'list': [
              {
                'vod_id': '1',
                'vod_name': '测试影片',
                'vod_year': '2026',
                'vod_pic': '${fixture.baseUri.resolve('poster.png')}',
                'type_name': '测试',
                'vod_content': '本地确定性样本，用于验证搜索、选集、播放与续播。',
                'vod_play_from': '测试线路',
                'vod_play_url':
                    '第01集\$${fixture.baseUri.resolve('sample.mp4')}#第02集\$${fixture.baseUri.resolve('ts/index.m3u8')}',
              },
            ],
          }),
        );
      } else {
        final target = File(
          p.joinAll([
            project,
            'test_support',
            'generated',
            ...request.uri.pathSegments,
          ]),
        );
        await serveLocalFile(
          request,
          target,
          contentType: request.uri.path.endsWith('.m3u8')
              ? 'application/vnd.apple.mpegurl'
              : 'application/octet-stream',
        );
      }
    });
  });
  tearDown(() async {
    await fixture.close();
    await services.close();
    await root.delete(recursive: true);
  });

  _nativeExportTest();
  _productFlowTest();
}

void _nativeExportTest() {
  testWidgets(
    'native offline HLS remux and full decode across variants',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('离线与导出验证'))),
      );
      final results = <Map<String, Object>>[];
      for (final sample in ['ts', 'fmp4', 'aes', 'ranges', 'separate']) {
        final directory = await Directory(p.join(root.path, sample)).create();
        final job = HlsDownload(
          id: sample,
          directory: directory,
          fetcher: services.fetcher,
          http: services.http,
          policy: HeaderPolicy({}),
          cancellation: CancellationToken(),
          maxBytes: 100 * 1024 * 1024,
          onProgress: (_, total, bytes) async {},
        );
        final entry = await job.run(
          fixture.baseUri.resolve('$sample/index.m3u8'),
        );
        final session = await services.offline.open(sample, directory, entry);
        try {
          for (final format in ExportFormat.values) {
            final result = await services.exporter.export(
              session.uri,
              p.join(root.path, '$sample.${format.name}'),
              format,
            );
            expect(result.duration.inSeconds, inInclusiveRange(11, 13));
            await services.exporter.validate(
              File(result.path),
              CancellationToken(),
            );
            results.add({
              'sample': sample,
              'format': format.name,
              'bytes': result.bytes,
              'durationMs': result.duration.inMilliseconds,
            });
          }
        } finally {
          session.close();
        }
      }
      await File(
        p.join(project, 'artifacts', 'native-export-results.json'),
      ).writeAsString(jsonEncode(results));
      binding.reportData = {'exports': results};
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

void _productFlowTest() {
  testWidgets(
    'product search detail playback history and responsive navigation',
    (tester) async {
      await services.sources.saveManual(
        '本地测试源',
        fixture.baseUri.resolve('api'),
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [servicesProvider.overrideWithValue(services)],
          child: RepaintBoundary(key: boundary, child: const ProductApp()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final router = GoRouter.of(tester.element(find.byType(AppShell)));
      await _homeExperience(tester, boundary, router);
      router.go('/search?q=测试');
      await pumpUntil(
        tester,
        () => find.byType(TextField).evaluate().isNotEmpty,
      );
      await pumpUntil(tester, () => find.text('测试影片').evaluate().isNotEmpty);
      await tester.tap(find.byType(PosterCard).first);
      await pumpUntil(
        tester,
        () => find.textContaining('API 可用').evaluate().isNotEmpty,
      );
      await tester.tap(find.widgetWithText(ListTile, '测试影片'));
      await pumpUntil(
        tester,
        () => find.text('播放 / 继续观看').evaluate().isNotEmpty,
      );
      await _downloadExperience(tester, boundary);
      await screenshot(boundary, 'product-detail.png');
      await tester.tap(find.text('播放 / 继续观看'));
      await pumpUntil(tester, () => find.byType(Video).evaluate().isNotEmpty);
      final video = tester.widget<Video>(find.byType(Video));
      await pumpUntil(
        tester,
        () => video.controller.player.state.position.inMilliseconds > 1200,
      );
      expect(video.controller.player.state.width, 640);
      expect(video.controller.player.state.height, 360);
      await _immersiveExperience(tester, boundary, video);
      await tester.tap(find.text('暂停'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(video.controller.player.state.playing, isFalse);
      await tester.tap(find.byTooltip('返回').first);
      await pumpUntil(tester, () => find.byType(Video).evaluate().isEmpty);
      final history = await services.history.all();
      expect(history.single.position.inMilliseconds, greaterThan(500));
      await _responsiveExperience(tester, boundary, router);
      await tester.pumpWidget(const SizedBox());
      await binding.setSurfaceSize(null);
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 20)) {
      throw StateError('Timed out waiting for product state');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> screenshot(GlobalKey key, String name) async {
  final image =
      await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
          .toImage();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      p.join(project, 'artifacts', name),
    ).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

Future<void> _responsiveExperience(
  WidgetTester tester,
  GlobalKey boundary,
  GoRouter router,
) async {
  router.go('/history');
  await pumpUntil(tester, () => find.text('测试影片').evaluate().isNotEmpty);
  expect(find.text('测试影片'), findsOneWidget);
  await binding.setSurfaceSize(const Size(390, 844));
  router.go('/settings');
  await tester.pump(const Duration(milliseconds: 250));
  expect(find.byType(NavigationBar), findsOneWidget);
  expect(tester.takeException(), isNull);
  await screenshot(boundary, 'product-phone-settings.png');
  await binding.setSurfaceSize(const Size(1280, 800));
  await services.settings.update({'mode': 'television'});
  router.go('/sources');
  await pumpUntil(tester, () => find.text('本地测试源').evaluate().isNotEmpty);
  expect(tester.takeException(), isNull);
  await screenshot(boundary, 'product-tv-sources.png');
}

Future<void> _homeExperience(
  WidgetTester tester,
  GlobalKey boundary,
  GoRouter router,
) async {
  await binding.setSurfaceSize(const Size(1280, 800));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('本地测试源').last);
  await pumpUntil(tester, () => find.text('AI剧场').evaluate().isNotEmpty);
  await tester.pump(const Duration(milliseconds: 300));
  await screenshot(boundary, 'enhancement-home-cinema.png');
  await services.settings.update({'theme': 'light'});
  await tester.pumpAndSettle();
  await screenshot(boundary, 'enhancement-home-light.png');
  await binding.setSurfaceSize(const Size(390, 844));
  await tester.pump(const Duration(milliseconds: 200));
  expect(tester.takeException(), isNull);
  await screenshot(boundary, 'enhancement-home-phone.png');
  await binding.setSurfaceSize(const Size(1280, 800));
  await services.settings.update({'theme': 'cinema'});
  await services.platform.setAppFullscreen(true);
  expect(await windowManager.isFullScreen(), isTrue);
  await services.platform.setAppFullscreen(false);
}

Future<void> _immersiveExperience(
  WidgetTester tester,
  GlobalKey boundary,
  Video video,
) async {
  await screenshot(boundary, 'enhancement-player-controls.png');
  await tester.pump(const Duration(seconds: 4));
  expect(find.text('暂停').hitTestable(), findsNothing);
  await screenshot(boundary, 'enhancement-player-immersive.png');
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.text('暂停'), findsOneWidget);
  await tester.tap(find.byTooltip('锁定防误触'));
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('暂停').hitTestable(), findsNothing);
  expect(find.byTooltip('解除防误触'), findsOneWidget);
  await tester.tap(find.byTooltip('解除防误触'));
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('暂停'), findsOneWidget);
  expect(tester.takeException(), isNull);
  await binding.setSurfaceSize(const Size(390, 844));
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byTooltip('静音').hitTestable(), findsOneWidget);
  expect(find.byTooltip('倍速').hitTestable(), findsOneWidget);
  await screenshot(boundary, 'experience-player-phone.png');
  expect(tester.takeException(), isNull);
  await binding.setSurfaceSize(const Size(844, 390));
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byTooltip('静音').hitTestable(), findsOneWidget);
  await screenshot(boundary, 'experience-player-landscape.png');
  expect(tester.takeException(), isNull);
  await binding.setSurfaceSize(const Size(1280, 800));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _downloadExperience(
  WidgetTester tester,
  GlobalKey boundary,
) async {
  await tester.tap(find.text('下载选集'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('全选'));
  await tester.pumpAndSettle();
  expect(find.text('下载 2 集'), findsOneWidget);
  await screenshot(boundary, 'enhancement-download-selection.png');
  await tester.tap(find.text('下载 2 集'));
  await pumpUntil(tester, () => find.text('下载选集 · 测试影片').evaluate().isEmpty);
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final tasks = await services.downloads.all();
    if (tasks.length == 2 && tasks.every((t) => t.status.name == 'complete')) {
      return;
    }
    if (tasks.any((t) => t.status.name == 'failed')) {
      throw StateError('Download failed: ${tasks.map((t) => t.error)}');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw StateError('Download queue did not complete');
}
