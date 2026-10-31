import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/app_theme.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/presentation/playback_surface.dart';
import 'package:zero_player/features/playback/presentation/player_transport.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import 'package:zero_player/media/hls/ts_timestamps.dart';
import '../test_support/fixture_project.dart';

final project = fixtureProjectRoot();
final _playerView = GlobalKey();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'timestamp resets remain monotonic and manual features skip twice',
    _playback,
    timeout: const Timeout(Duration(minutes: 4)),
  );
  testWidgets(
    'unnamed segments without discontinuity tags also keep time and features',
    (tester) => _playback(tester, unmarked: true),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _playback(WidgetTester tester, {bool unmarked = false}) async {
  final root = await Directory.systemTemp.createTemp('timestamp-native-');
  final services = AppServices.scoped(
    root,
    AppDatabase.memory(),
    allowPrivateNetworks: true,
  );
  final server = await _server(root, unmarked: unmarked);
  final engine = MediaKitEngine(
    isTrustedResource: services.gateway.isRegisteredResource,
    isTrustedPlaylist: services.gateway.isRegisteredPlaylist,
  );
  final controller = PlaybackController(services, engine);
  final errors = engine.errors.listen((error) {
    // ignore: avoid_print
    print('NATIVE_ERROR $error');
  });
  final regressions = <String>[];
  Duration? previous;
  var monitor = false;
  final subscription = engine.position.listen((value) {
    if (monitor &&
        previous != null &&
        value + const Duration(seconds: 1) < previous!) {
      regressions.add('$previous -> $value');
    }
    previous = value;
  });
  try {
    await services.settings.load();
    await services.supervision.load();
    await services.gateway.start();
    await services.settings.update({
      'contentFilter': true,
      'filterKeywords': false,
      'autoplay': false,
    });
    await tester.pumpWidget(_player(controller, engine));
    final item = _item(server.port);
    await controller.open(PlaybackRequest(item));
    // ignore: avoid_print
    print(
      'NATIVE_OPEN error=${controller.error} gateway=${services.gateway.failures}',
    );
    await _until(
      () => controller.originalPosition > const Duration(seconds: 1),
    );
    await _saveControlsImage(tester);
    monitor = true;
    await _until(
      () => controller.originalPosition > const Duration(seconds: 13),
    );
    monitor = false;
    expect(regressions, isEmpty);
    final image = await engine.screenshot();
    expect(image, isNotNull);
    expect(image!.length, greaterThan(1000));
    final captured = await _capture(controller);
    // A different work forces fingerprint matching; same-work range skips
    // must not make the native matching regression pass by themselves.
    final rule = FeatureRule.fromJson({
      ...captured.toJson(),
      'originKey': 'another-work',
    });
    await services.filterFeatures.save(rule);
    await controller.refreshFeatureRules();
    await controller.seek(const Duration(milliseconds: 123));
    await engine.play();
    await _until(() => controller.canUndoSkip);
    await _until(
      () => controller.originalPosition >= const Duration(seconds: 12),
    );
    expect(controller.notice, contains('广告画面'));
    final skipped = controller.originalPosition;
    await controller.undoSkip();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(controller.originalPosition, lessThan(skipped));
    expect(controller.canUndoSkip, isFalse);
    await controller.seek(Duration.zero);
    await _until(() => controller.canUndoSkip);
    expect(controller.error, isNull);
    // ignore: avoid_print
    print(
      'DISCONTINUITY_NATIVE monotonic=true screenshot=${image.length} repeatedFeatureSkip=${controller.notice}',
    );
  } finally {
    await subscription.cancel();
    await errors.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.close();
    await services.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  }
}

CatalogItem _item(int port) => CatalogItem(
  sourceId: 'fixture',
  id: 'reset',
  title: '时间戳回零素材',
  lines: [
    PlayLine('main', [
      Episode('1', Uri.parse('http://127.0.0.1:$port/index.m3u8')),
    ]),
  ],
);

Widget _player(PlaybackController controller, MediaKitEngine engine) =>
    MaterialApp(
      theme: buildAppTheme(Brightness.dark, false, 'cinema'),
      home: Scaffold(
        body: RepaintBoundary(
          key: _playerView,
          child: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => PlaybackSurface(
              controller: controller,
              video: Video(controller: engine.video, controls: NoVideoControls),
              transport: PlayerTransport(
                controller: controller,
                fullscreen: false,
                fit: BoxFit.contain,
                onFullscreen: () {},
                onOptions: () {},
                onMark: () {},
                onScreenshot: () {},
                onFit: (_) {},
              ),
              title: '时间轴与播放器控件 · 本地回归素材',
              onBack: () {},
              onOptions: () {},
              locked: false,
              onLock: (_) {},
              gestures: true,
            ),
          ),
        ),
      ),
    );

Future<void> _saveControlsImage(WidgetTester tester) async {
  await tester.pump();
  final boundary =
      _playerView.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$project/.tools/content-filter/player-controls.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

Future<HttpServer> _server(Directory root, {required bool unmarked}) async {
  for (var i = 0; i < 4; i++) {
    final original = File(
      '$project/test_support/generated/content_filter/hls/seg_${i.toString().padLeft(3, '0')}.ts',
    );
    final bytes = normalizeTsTimestamps(
      await original.readAsBytes(),
      Duration.zero,
    );
    await File('${root.path}/part$i.ts').writeAsBytes(bytes);
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      if (request.uri.path == '/index.m3u8') {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        request.response.write(
          [
            '#EXTM3U',
            '#EXT-X-VERSION:3',
            '#EXT-X-TARGETDURATION:4',
            '#EXT-X-MEDIA-SEQUENCE:0',
            for (var i = 0; i < 4; i++) ...[
              if (i > 0 && !unmarked) '#EXT-X-DISCONTINUITY',
              '#EXTINF:4.0,',
              unmarked ? 'part$i' : 'part$i.ts',
            ],
            '#EXT-X-ENDLIST',
          ].join('\n'),
        );
      } else if (RegExp(r'^/part[0-3](\.ts)?$').hasMatch(request.uri.path)) {
        await serveLocalFile(
          request,
          File('${root.path}${request.uri.path}${unmarked ? '.ts' : ''}'),
          contentType: 'video/mp2t',
        );
      } else {
        request.response.statusCode = 404;
      }
    } finally {
      await request.response.close();
    }
  });
  return server;
}

Future<void> _until(bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 35)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue);
}

Future<FeatureRule> _capture(PlaybackController controller) =>
    controller.captureFeature(
      from: const Duration(seconds: 4),
      to: const Duration(seconds: 6),
      label: '广告画面',
      mode: FeatureMode.visual,
      beforeMs: 0,
      afterMs: 6000,
      token: CancellationToken(),
    );
