import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/features/downloads/application/download_scheduler.dart';
import 'package:zero_player/features/downloads/domain/download_task.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/playback/application/local_video.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import 'package:zero_player/media/export/media_exporter.dart';
import '../test_support/fixture_project.dart';
import '../test_support/native_mark_harness.dart' show nativeWidgetUntil;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'HLS download saves a standalone MP4 to chosen directory',
    _hlsOutput,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  testWidgets(
    'local video decodes, seeks, resumes and exports to chosen directory',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('local-native-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      await services.settings.load();
      await services.supervision.load();
      await services.settings.update({'autoplay': false});
      final engine = MediaKitEngine(
        isTrustedResource: services.offline.isRegisteredResource,
        isTrustedPlaylist: services.offline.isRegisteredPlaylist,
      );
      final controller = PlaybackController(services, engine);
      try {
        final selected = await File(
          '${fixtureProjectRoot()}/test_support/generated/content_filter/long.mp4',
        ).copy('${root.path}/本地 视频.mp4');
        await tester.pumpWidget(
          MaterialApp(
            home: Video(controller: engine.video, controls: NoVideoControls),
          ),
        );
        final request = await LocalVideo.open(services, selected.path);
        await controller.open(request);
        await nativeWidgetUntil(
          tester,
          () => controller.originalPosition > const Duration(seconds: 1),
        );
        expect(engine.player.state.width, greaterThan(0));
        await controller.seek(const Duration(seconds: 4));
        await nativeWidgetUntil(
          tester,
          () => controller.originalPosition >= const Duration(seconds: 4),
        );
        await engine.pause();
        await controller.save();
        final reopened = await LocalVideo.open(services, selected.path);
        expect(
          reopened.position,
          greaterThanOrEqualTo(const Duration(seconds: 4)),
        );
        reopened.offline!.close();
        final destination = await Directory('${root.path}/chosen').create();
        final output = '${destination.path}/saved.mp4';
        await services.exporter.export(
          request.offline!.uri,
          output,
          ExportFormat.mp4,
        );
        await services.exporter.validate(File(output), CancellationToken());
        expect(await File(output).length(), greaterThan(0));
        final saved = await LocalVideo.open(services, output);
        await controller.open(saved);
        await nativeWidgetUntil(
          tester,
          () => controller.originalPosition > const Duration(seconds: 1),
        );
        expect(controller.error, isNull);
      } finally {
        await controller.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await services.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _hlsOutput(WidgetTester tester) async {
  final root = await Directory.systemTemp.createTemp('hls-output-');
  final services = AppServices.scoped(
    root,
    AppDatabase.memory(),
    allowPrivateNetworks: true,
  );
  await services.settings.load();
  await services.supervision.load();
  await services.store.initialize();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      final name = request.uri.pathSegments.last;
      await serveLocalFile(
        request,
        File('${fixtureProjectRoot()}/test_support/generated/ts/$name'),
        contentType: name.endsWith('.m3u8')
            ? 'application/vnd.apple.mpegurl'
            : 'video/mp2t',
      );
    } finally {
      await request.response.close();
    }
  });
  final scheduler = DownloadScheduler(
    services.downloads,
    services.fetcher,
    services.http,
    services.offline,
    services.settings,
    validateMp4: services.exporter.validate,
    exporter: services.exporter,
  );
  try {
    final destination = await Directory('${root.path}/chosen').create();
    final episode = Episode(
      '1',
      Uri.parse('http://127.0.0.1:${server.port}/index.m3u8'),
    );
    final line = PlayLine('main', [episode]);
    final item = CatalogItem(
      sourceId: 'native-test',
      id: 'hls',
      title: 'HLS test',
      lines: [line],
    );
    final id = await services.downloads.create(
      item,
      line,
      episode,
      {},
      destination: destination.path,
    );
    scheduler.kick();
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (await services.downloads.output(id, saved: true) == null) {
      final task = (await services.downloads.find(id))!;
      if (task.status == DownloadStatus.failed) {
        fail(task.error ?? 'Download failed');
      }
      if (DateTime.now().isAfter(end)) fail('Download timed out');
      await tester.pump(const Duration(milliseconds: 100));
    }
    final saved = File((await services.downloads.output(id, saved: true))!);
    await services.exporter.validate(saved, CancellationToken());
    expect(await saved.length(), greaterThan(0));
    await scheduler.remove(id);
    expect(await saved.exists(), isTrue);
  } finally {
    await scheduler.close();
    await services.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  }
}
