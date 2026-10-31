import 'package:zero_player/core/platform/video_files.dart';
import 'package:zero_player/core/platform/platform_services.dart';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/product_app.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/downloads/application/download_output.dart';
import 'package:zero_player/features/playback/application/local_video.dart';
import 'package:zero_player/features/downloads/domain/download_task.dart';
import 'package:zero_player/media/export/media_exporter.dart';

void main() {
  _regression0();
  _regression1();
  _regression2();
  _regression3();
}

void _regression0() {
  test('another document ignores previous identity and progress', () async {
    final root = await Directory.systemTemp.createTemp('recheck-id-');
    final services = AppServices.scoped(root, AppDatabase.memory());
    try {
      await services.settings.load();
      await services.supervision.load();
      final a = await File('${root.path}/a.mp4').writeAsBytes([1]);
      final b = await File('${root.path}/b.mp4').writeAsBytes([2]);
      final first = await LocalVideo.open(
        services,
        a.path,
        documentIdentity: 'document-A',
      );
      await services.history.save(
        first.item,
        first.item.lines.single,
        first.item.lines.single.episodes.single,
        const Duration(seconds: 20),
        const Duration(seconds: 100),
      );
      first.offline!.close();
      final second = await LocalVideo.open(
        services,
        b.path,
        previousId: first.item.id,
        documentIdentity: 'document-B',
      );
      expect(second.item.id, isNot(first.item.id));
      expect(second.position, Duration.zero);
      second.offline!.close();
    } finally {
      await services.close();
      await root.delete(recursive: true);
    }
  });
}

void _regression1() {
  test(
    'published save intent recovers without exporting or overwriting',
    () async {
      final root = await Directory.systemTemp.createTemp('recheck-publish-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      try {
        await services.settings.load();
        await services.supervision.load();
        await services.store.initialize();
        final dest = await Directory('${root.path}/chosen').create();
        final e = Episode('1', Uri.parse('https://example.invalid/a.mp4'));
        final l = PlayLine('main', [e]);
        final item = CatalogItem(
          sourceId: 'test',
          id: 'one',
          title: 'movie',
          lines: [l],
        );
        final id = await services.downloads.create(
          item,
          l,
          e,
          {},
          destination: dest.path,
        );
        final task = (await services.downloads.find(id))!;
        await File('${task.directory}/video.mp4').writeAsBytes([1, 2, 3]);
        await File('${task.directory}/integrity.json').writeAsString(
          jsonEncode({
            'bytes': 3,
            'digest': '${sha256.convert([1, 2, 3])}',
          }),
        );
        await services.downloads.cacheComplete(id, 'video.mp4');
        final published = await File(
          '${dest.path}/${task.title}-$id.mp4',
        ).writeAsBytes([1, 2, 3]);
        await services.db.write('INSERT INTO app_meta(key,value) VALUES(?,?)', [
          'download_publish:$id',
          jsonEncode({
            'destination': dest.path,
            'name': published.uri.pathSegments.last,
            'digest': '${sha256.convert([1, 2, 3])}',
          }),
        ]);
        await services.downloads.recover();
        expect(
          (await services.downloads.find(id))!.status,
          DownloadStatus.pendingSave,
        );
        for (var retry = 0; retry < 2; retry++) {
          await saveDownloadOutput(
            (await services.downloads.find(id))!,
            services.downloads,
            services.offline,
            _Exporter(),
            CancellationToken(),
          );
        }
        expect(await published.readAsBytes(), [1, 2, 3]);
        expect(
          p.normalize((await services.downloads.output(id, saved: true))!),
          p.normalize(published.path),
        );
      } finally {
        await services.close();
        await root.delete(recursive: true);
      }
    },
  );
}

void _regression2() {
  test('recovery verifies bytes and preserves unrelated targets', () async {
    final root = await Directory.systemTemp.createTemp('publish-verify-');
    try {
      final file = await File('${root.path}/existing.mp4').writeAsBytes([9]);
      await expectLater(
        VideoFiles.recoverSave(
          root.path,
          'existing.mp4',
          '${sha256.convert([1])}',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.readAsBytes(), [9]);
      expect(
        await VideoFiles.recoverSave(
          root.path,
          'missing.mp4',
          '${sha256.convert([1])}',
        ),
        isNull,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}

void _regression3() {
  testWidgets('hidden owner reveals itself without waiting for a frame', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('recheck-hidden-'),
    ))!;
    final opens = (await tester.runAsync(
      () async => StreamController<String>(sync: true),
    ))!;
    final services = (await tester.runAsync(
      () async => AppServices.scoped(
        root,
        AppDatabase.memory(),
        openRequests: opens.stream,
        platform: PlatformServices(applyFullscreen: (_, _) async {}),
      ),
    ))!;
    var shows = 0;
    const channel = MethodChannel('window_manager');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'show') shows++;
          if (call.method == 'isMinimized') return false;
          return null;
        });
    try {
      await tester.runAsync(() async {
        await services.settings.load();
        await services.supervision.load();
        await services.settings.update({
          'recommendation': 'off',
          'backgroundProbe': false,
          'navigationGuideSeen': true,
          'startFullscreen': false,
        });
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [servicesProvider.overrideWithValue(services)],
          child: const ProductApp(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(tester.binding.framesEnabled, isFalse);
      opens.add('${root.path}/movie.mp4');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(shows, 1);

      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.runAsync(() async {
        await services.close();
        await opens.close();
        await root.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}

class _Exporter implements MediaExporter {
  @override
  Future<ExportResult> export(
    Uri input,
    String output,
    ExportFormat format, {
    CancellationToken? cancellation,
  }) async {
    await File(output).writeAsBytes([1, 2, 3]);
    return ExportResult(output, 3, const Duration(seconds: 1));
  }
}
