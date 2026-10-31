import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/presentation/feature_rule_dialog.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import 'fixture_project.dart';

final fixtureProject = fixtureProjectRoot();

final class NativeMarkHarness {
  NativeMarkHarness._(this.root, this.services, this.server)
    : engine = MediaKitEngine(
        isTrustedPlaylist: services.gateway.isRegisteredPlaylist,
      ) {
    player = PlaybackController(services, engine);
  }
  final Directory root;
  final AppServices services;
  final HttpServer server;
  final MediaKitEngine engine;
  late final PlaybackController player;

  static Future<NativeMarkHarness> create() async {
    final root = await Directory.systemTemp.createTemp('native-mark-');
    final services = AppServices.scoped(
      root,
      AppDatabase.memory(),
      allowPrivateNetworks: true,
    );
    await services.settings.load();
    await services.supervision.load();
    await services.gateway.start();
    await services.settings.update({
      'autoplay': false,
      'filterKeywords': false,
    });
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        final name = request.uri.pathSegments.last;
        final custom = File('${root.path}/$name');
        await serveLocalFile(
          request,
          await custom.exists()
              ? custom
              : File(
                  '$fixtureProject/test_support/generated/content_filter/$name',
                ),
          contentType: 'video/mp4',
        );
      } finally {
        await request.response.close();
      }
    });
    return NativeMarkHarness._(root, services, server);
  }

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Stack(
            children: [
              Video(controller: engine.video, controls: NoVideoControls),
              Align(
                alignment: Alignment.topLeft,
                child: TextButton(
                  onPressed: () =>
                      editFeatureRule(context, player, quickCapture: true),
                  child: const Text('标记广告'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> open(String file, {String source = 'test-source'}) async {
    await player.open(
      PlaybackRequest(
        CatalogItem(
          sourceId: source,
          id: file,
          title: '标记恢复测试',
          lines: [
            PlayLine('main', [
              Episode('1', Uri.parse('http://127.0.0.1:${server.port}/$file')),
            ]),
          ],
        ),
      ),
    );
    await nativeUntil(() => player.state.duration > Duration.zero);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await player.close();
    await services.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  }
}

Future<void> nativeUntil(bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 35)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue);
}

Future<void> nativeWidgetUntil(
  WidgetTester tester,
  bool Function() ready,
) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 40)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue);
}
