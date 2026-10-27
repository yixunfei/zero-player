import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import '../test_support/http_test_server.dart';

const configuredProject = String.fromEnvironment('PROJECT_ROOT');
final project = configuredProject.isEmpty
    ? Directory.current.path
    : configuredProject;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'website resolvers feed native playback through the media gateway',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'zero-website-playback-',
      );
      final services = AppServices.scoped(root, AppDatabase.memory());
      final engine = MediaKitEngine();
      final controller = PlaybackController(services, engine);
      late HttpTestServer fixture;
      fixture = await HttpTestServer.start(
        (request) => _serve(request, fixture.baseUri),
      );
      try {
        await services.settings.load();
        await services.settings.update({
          'autoplay': false,
          'backgroundProbe': false,
        });
        await services.store.initialize();
        await services.gateway.start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Video(controller: engine.video)),
          ),
        );
        for (final kind in ['macCmsHtml', 'kanju']) {
          final id = await services.sources.saveManual(
            kind,
            fixture.baseUri,
            kind: kind,
          );
          final item = await services.detail(id, '1');
          expect(item.lines.single.episodes.single.requiresResolution, isTrue);
          await controller.open(PlaybackRequest(item));
          final watch = Stopwatch()..start();
          while (engine.snapshot.position.inMilliseconds < 1000 &&
              watch.elapsed.inSeconds < 20) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(controller.error, isNull);
          expect(
            engine.snapshot.position.inMilliseconds,
            greaterThanOrEqualTo(1000),
          );
          expect(engine.player.state.width, 640);
          expect(engine.player.state.height, 360);
          expect(controller.resolvedMedia!.uri.path, '/ts/index.m3u8');
          await controller.save();
          expect(
            (await services.history.all()).any((h) => h.sourceId == id),
            isTrue,
          );
        }
        expect(fixture.calls['/vodplay/1-1-1.html'], 1);
        expect(fixture.calls['/v1/playback/resolve/one'], 2);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await controller.close();
        await services.close();
        await fixture.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _serve(HttpRequest request, Uri base) async {
  final path = request.uri.path;
  if (path == '/voddetail/1.html') {
    request.response.write(
      '<h1>测试影片</h1><a href="/vodplay/1-1-1.html">第1集</a>',
    );
  } else if (path == '/vodplay/1-1-1.html') {
    final data = jsonEncode({
      'encrypt': 0,
      'url': '${base.resolve('ts/index.m3u8')}',
    });
    request.response.write('<script>var player_aaaa=$data;</script>');
  } else if (path.startsWith('/v1/')) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(
        path == '/v1/catalog/1'
            ? {
                'id': '1',
                'title': '测试影片',
                'episodes': [
                  {'title': '第1集', 'token': 'one'},
                ],
              }
            : {
                'line_options': [
                  {
                    'provider_id': 'direct',
                    'provider_name': '测试直连',
                    'resolved': true,
                    'url': '${base.resolve('ts/index.m3u8')}',
                  },
                ],
              },
      ),
    );
  } else {
    await serveLocalFile(
      request,
      File(
        p.joinAll([
          project,
          'test_support',
          'generated',
          ...request.uri.pathSegments,
        ]),
      ),
      contentType: path.endsWith('.m3u8')
          ? 'application/vnd.apple.mpegurl'
          : 'application/octet-stream',
    );
  }
}
