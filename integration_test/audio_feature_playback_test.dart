import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import '../test_support/fixture_project.dart';

final project = fixtureProjectRoot();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'saved audio matches other work after non-grid seek and first enable',
    _playback,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _playback(WidgetTester tester) async {
  final root = await Directory.systemTemp.createTemp('audio-feature-');
  final services = AppServices.scoped(
    root,
    AppDatabase.memory(),
    allowPrivateNetworks: true,
  );
  final engine = MediaKitEngine(
    isTrustedResource: services.gateway.isRegisteredResource,
    isTrustedPlaylist: services.gateway.isRegisteredPlaylist,
  );
  final controller = PlaybackController(services, engine);
  final server = await _server();
  try {
    await services.settings.load();
    await services.supervision.load();
    await services.gateway.start();
    await services.settings.update({
      'contentFilter': false,
      'filterKeywords': false,
      'autoplay': false,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Video(controller: engine.video, controls: NoVideoControls),
        ),
      ),
    );
    await controller.open(
      PlaybackRequest(
        CatalogItem(
          sourceId: 'audio-source',
          id: 'voice',
          title: '合成口播',
          lines: [
            PlayLine('main', [
              Episode(
                '1',
                Uri.parse('http://127.0.0.1:${server.port}/voice.mp4'),
              ),
            ]),
          ],
        ),
      ),
    );
    await _until(() => controller.state.duration > Duration.zero);
    final rule = await controller.captureFeature(
      from: const Duration(seconds: 4),
      to: const Duration(milliseconds: 8500),
      label: '音频广告',
      mode: FeatureMode.audio,
      beforeMs: 0,
      afterMs: 5500,
      token: CancellationToken(),
    );
    expect(rule.audio, hasLength(18));
    expect(rule.visual, isEmpty);
    await services.filterFeatures.save(
      FeatureRule.fromJson({
        ...rule.toJson(),
        'originKey': 'different-episode',
      }),
    );
    await services.settings.update({'contentFilter': true});
    await controller.refreshFeatureRules();
    await controller.seek(const Duration(milliseconds: 123));
    await engine.play();
    await _until(() => controller.canUndoSkip);
    await _until(
      () => controller.originalPosition >= const Duration(seconds: 14),
    );
    expect(controller.notice, contains('命中内容特征：音频广告'));
    await controller.undoSkip();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(controller.canUndoSkip, isFalse);
    await controller.seek(const Duration(milliseconds: 123));
    await _until(() => controller.canUndoSkip);
    expect(controller.error, isNull);
    // ignore: avoid_print
    print('AUDIO_FEATURE_NATIVE first-enable=true cross-work=true repeat=true');
  } finally {
    // ignore: avoid_print
    print(controller.diagnosticReport());
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.close();
    await services.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  }
}

Future<void> _until(bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 35)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue);
}

Future<HttpServer> _server() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      await serveLocalFile(
        request,
        File('$project/test_support/generated/content_filter/voice.mp4'),
        contentType: 'video/mp4',
      );
    } finally {
      await request.response.close();
    }
  });
  return server;
}
