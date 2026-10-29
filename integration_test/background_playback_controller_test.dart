import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/media/content_filter/keyword_models.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';

const project = String.fromEnvironment(
  'PROJECT_ROOT',
  defaultValue: 'L:/zero-player',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'background keywords require confirmation and undo remains usable',
    _playback,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _playback(WidgetTester tester) async {
  final root = await Directory.systemTemp.createTemp('background-controller-');
  final services = AppServices.scoped(
    root,
    AppDatabase.memory(),
    allowPrivateNetworks: true,
  );
  final engine = MediaKitEngine(
    isTrustedPlaylist: services.gateway.isRegisteredPlaylist,
  );
  final player = PlaybackController(services, engine);
  try {
    await services.settings.load();
    await services.supervision.load();
    await services.gateway.start();
    await _installFixtures(root);
    await services.settings.update({
      'contentFilter': true,
      'filterSkipSeconds': 5,
      'autoplay': false,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Video(controller: engine.video, controls: NoVideoControls),
        ),
      ),
    );
    final item = CatalogItem(
      sourceId: 'fixture',
      id: 'voice',
      title: '口播测试',
      lines: [
        PlayLine('main', [
          Episode(
            '1',
            Uri.parse('http://127.0.0.1:9763/content_filter/voice.mp4'),
          ),
        ]),
      ],
    );
    await player.open(PlaybackRequest(item));
    await _until(() => player.pendingFeature != null);
    expect(player.canUndoSkip, isFalse);
    expect(player.pendingFeature!.requiresConfirmation, isTrue);
    final target = player.pendingFeature!.range.end;
    expect(player.originalPosition, lessThan(target));
    player.confirmFeatureSkip();
    await _until(() => player.canUndoSkip);
    expect(player.error, isNull);
    expect(player.notice, contains('澳门'));
    await _until(() => player.originalPosition >= target);
    final afterSkip = player.originalPosition;
    await player.undoSkip();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(player.originalPosition, lessThan(afterSkip));
    expect(player.canUndoSkip, isFalse);
    // ignore: avoid_print
    print(
      'BACKGROUND_CONTROLLER afterSkip=$afterSkip undo=${player.originalPosition} error=${player.error}',
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await player.close();
    await services.close();
    try {
      await root.delete(recursive: true);
    } on PathAccessException {
      // Windows keeps explicitly loaded inference DLLs mapped until exit.
      if (!Platform.isWindows) rethrow;
      final background = Directory('${root.path}/content_filter/background');
      if (background.existsSync()) expect(background.listSync(), isEmpty);
    }
  }
}

Future<void> _installFixtures(Directory root) async {
  final runtime = await Directory(
    '${root.path}/content_filter/runtime',
  ).create(recursive: true);
  for (final name in ['onnxruntime.dll', 'sherpa-onnx-c-api.dll']) {
    await File(
      '$project/.tools/content-filter/runtime/$name',
    ).copy('${runtime.path}/$name');
  }
  final model = await Directory(
    '${root.path}/content_filter/keywords',
  ).create(recursive: true);
  for (final asset in KeywordModels.assets) {
    await File(
      '$project/.tools/content-filter/kws-source/${KeywordModels.prefix}/${asset.name}',
    ).copy('${model.path}/${asset.name}');
  }
}

Future<void> _until(bool Function() complete) async {
  final watch = Stopwatch()..start();
  while (!complete() && watch.elapsed < const Duration(seconds: 30)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(complete(), isTrue);
}
