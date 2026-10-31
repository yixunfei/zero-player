import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import 'package:zero_player/core/platform/video_files.dart';
import 'package:zero_player/core/platform/publish_file.dart';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/downloads/application/download_scheduler.dart';
import 'package:zero_player/features/downloads/domain/download_task.dart';
import 'package:zero_player/features/playback/application/local_video.dart';
import 'package:zero_player/media/export/media_exporter.dart';

late Directory root;
late AppServices services;

void main() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('local-output-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.settings.load();
    await services.supervision.load();
    await services.store.initialize();
  });
  tearDown(() async {
    await services.close();
    await root.delete(recursive: true);
  });

  test(
    'selected local file supports range and revokes access on close',
    () async {
      final video = await File(
        '${root.path}/本地 视频.MKV',
      ).writeAsBytes([0, 1, 2, 3, 4]);
      await File('${root.path}/private.txt').writeAsString('private');
      final request = await LocalVideo.open(services, video.path);
      final session = request.offline!;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final range = await client.getUrl(session.uri);
      range.headers.set('range', 'bytes=1-3');
      final response = await range.close();
      expect(response.statusCode, 206);
      expect(await response.expand((v) => v).toList(), [1, 2, 3]);
      final adjacent = await (await client.getUrl(
        session.uri.resolve('private.txt'),
      )).close();
      expect(adjacent.statusCode, 404);
      await adjacent.drain<void>();
      session.close();
      expect(services.offline.isRegisteredResource(session.uri), isFalse);
      final revoked = await (await client.getUrl(session.uri)).close();
      expect(revoked.statusCode, 404);
      await revoked.drain<void>();
    },
  );

  test(
    'local playlists and missing files cannot become trusted resources',
    () async {
      final playlist = await File(
        '${root.path}/unsafe.m3u8',
      ).writeAsString('#EXTM3U');
      await expectLater(
        LocalVideo.open(services, playlist.path),
        throwsFormatException,
      );
      await expectLater(
        LocalVideo.open(services, '${root.path}/missing.mp4'),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('local video restores progress and obeys title filtering', () async {
    final file = await File('${root.path}/movie.mp4').writeAsBytes([1, 2]);
    final first = await LocalVideo.open(services, file.path);
    await services.history.save(
      first.item,
      first.item.lines.single,
      first.item.lines.single.episodes.single,
      const Duration(seconds: 8),
      const Duration(seconds: 40),
    );
    first.offline!.close();
    final reopened = await LocalVideo.open(services, file.path);
    expect(reopened.position, const Duration(seconds: 8));
    reopened.offline!.close();
    final blocked = await File('${root.path}/成人色情.mp4').writeAsBytes([1]);
    await expectLater(
      LocalVideo.open(services, blocked.path),
      throwsA(isA<ContentBlocked>()),
    );
  });

  _fileSafetyTests();
  _interruptedSaveTest();
  _legacyRecoveryTest();
  _localReselectTest();
  _outputRetryTest();
}

void _fileSafetyTests() {
  test('saving never overwrites an existing file', () async {
    final original = await File('${root.path}/saved.mp4').writeAsBytes([7, 8]);
    final source = await File('${root.path}/source.mp4').writeAsBytes([1, 2]);
    await expectLater(
      VideoFiles.save(source, root.path, 'saved.mp4'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await original.readAsBytes(), [7, 8]);
  });
  test(
    'publishing preserves a target created after the initial existence check',
    () async {
      final target = await File(
        '${root.path}/collision.mp4',
      ).writeAsBytes([7, 8]);
      final temporary = await File(
        '${root.path}/new.part',
      ).writeAsBytes([1, 2]);
      await expectLater(
        publishFile(temporary, target),
        throwsA(isA<FileSystemException>()),
      );
      expect(await target.readAsBytes(), [7, 8]);
      expect(await temporary.readAsBytes(), [1, 2]);
    },
  );
}

void _interruptedSaveTest() {
  test(
    'interrupted save resumes from verified cache and removes stale work',
    () async {
      final destination = await Directory('${root.path}/chosen').create();
      final episode = Episode(
        '1',
        Uri.parse('https://invalid.example/video.mp4'),
      );
      final line = PlayLine('main', [episode]);
      final item = CatalogItem(
        sourceId: 'test',
        id: 'resume',
        title: '视频',
        lines: [line],
      );
      final id = await services.downloads.create(
        item,
        line,
        episode,
        {},
        destination: destination.path,
      );
      final task = (await services.downloads.find(id))!;
      final bytes = [0, 1, 2, 3];
      await File('${task.directory}/video.mp4').writeAsBytes(bytes);
      await File('${task.directory}/integrity.json').writeAsString(
        jsonEncode({'bytes': 4, 'digest': '${sha256.convert(bytes)}'}),
      );
      await File('${task.directory}/output.mp4').writeAsBytes([9]);
      final stale = await Directory('${task.directory}/.save-crashed').create();
      await File('${stale.path}/part').writeAsBytes([9]);
      await services.downloads.cacheComplete(id, 'video.mp4');
      expect(
        (await services.downloads.find(id))!.status,
        DownloadStatus.pendingSave,
      );
      await services.downloads.status(id, DownloadStatus.saving);
      var networkAttempts = 0;
      final scheduler = DownloadScheduler(
        services.downloads,
        services.fetcher,
        services.http,
        services.offline,
        services.settings,
        validateMp4: (_, _) async {},
        exporter: _CopyExporter(),
        resolve: (task, _) async {
          networkAttempts++;
          return task;
        },
      );
      addTearDown(scheduler.close);
      await scheduler.initialize();
      await _until(
        () async =>
            (await services.downloads.find(id))!.status ==
            DownloadStatus.complete,
      );
      expect(networkAttempts, 0);
      expect(
        await File(
          (await services.downloads.output(id, saved: true))!,
        ).readAsBytes(),
        bytes,
      );
      expect(await File('${task.directory}/output.mp4').exists(), isFalse);
      expect(await stale.exists(), isFalse);
    },
  );
}

void _legacyRecoveryTest() {
  test(
    'legacy complete with unpublished target is recovered as pending',
    () async {
      final episode = Episode(
        '1',
        Uri.parse('https://invalid.example/video.mp4'),
      );
      final line = PlayLine('main', [episode]);
      final item = CatalogItem(
        sourceId: 'test',
        id: 'legacy',
        title: '视频',
        lines: [line],
      );
      final id = await services.downloads.create(
        item,
        line,
        episode,
        {},
        destination: '${root.path}/chosen',
      );
      await services.downloads.complete(id, 'video.mp4');
      await services.downloads.recover();
      final task = (await services.downloads.find(id))!;
      expect(task.status, DownloadStatus.pendingSave);
      expect(task.localPath, 'video.mp4');
    },
  );
}

void _localReselectTest() {
  test('reselected local file retains history identity and position', () async {
    final old = await File('${root.path}/old.mp4').writeAsBytes([1]);
    final first = await LocalVideo.open(services, old.path);
    await services.history.save(
      first.item,
      first.item.lines.single,
      first.item.lines.single.episodes.single,
      const Duration(seconds: 8),
      const Duration(seconds: 40),
    );
    first.offline!.close();
    final replacement = await File(
      '${root.path}/replacement.mp4',
    ).writeAsBytes([2]);
    final reopened = await LocalVideo.open(
      services,
      replacement.path,
      previousId: first.item.id,
    );
    expect(reopened.item.id, first.item.id);
    expect(reopened.position, const Duration(seconds: 8));
    reopened.offline!.close();
  });
}

void _outputRetryTest() {
  test(
    'failed destination save retries cached media without network and keeps saved video on removal',
    () async {
      final destination = Directory('${root.path}/chosen');
      final episode = Episode(
        '1',
        Uri.parse('https://invalid.example/video.mp4'),
      );
      final line = PlayLine('main', [episode]);
      final item = CatalogItem(
        sourceId: 'test',
        id: 'one',
        title: '视频',
        lines: [line],
      );
      final repository = services.downloads;
      final id = await repository.create(
        item,
        line,
        episode,
        {},
        destination: destination.path,
      );
      final task = (await repository.find(id))!;
      final file = await File(
        '${task.directory}/video.mp4',
      ).writeAsBytes([0, 1, 2, 3]);
      await File('${task.directory}/integrity.json').writeAsString(
        jsonEncode({
          'bytes': 4,
          'digest': '${sha256.convert(await file.readAsBytes())}',
        }),
      );
      await repository.complete(id, 'video.mp4');
      var networkAttempts = 0;
      final scheduler = DownloadScheduler(
        repository,
        services.fetcher,
        services.http,
        services.offline,
        services.settings,
        validateMp4: (_, _) async {},
        exporter: _CopyExporter(),
        resolve: (task, _) async {
          networkAttempts++;
          return task;
        },
      );
      addTearDown(scheduler.close);
      await scheduler.resume(id);
      await _until(
        () async =>
            (await repository.find(id))!.status == DownloadStatus.failed,
      );
      expect((await repository.find(id))!.localPath, 'video.mp4');
      await destination.create();
      await scheduler.resume(id);
      await _until(
        () async =>
            await repository.output(id, saved: true) != null &&
            (await repository.find(id))!.status == DownloadStatus.complete,
      );
      expect(networkAttempts, 0);
      final saved = File((await repository.output(id, saved: true))!);
      expect(await saved.readAsBytes(), [0, 1, 2, 3]);
      await scheduler.remove(id);
      expect(await saved.exists(), isTrue);
      expect(await Directory(task.directory).exists(), isFalse);
    },
  );
}

Future<void> _until(Future<bool> Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!await condition()) {
    if (DateTime.now().isAfter(end)) fail('condition timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

final class _CopyExporter implements MediaExporter {
  @override
  Future<ExportResult> export(
    Uri input,
    String output,
    ExportFormat format, {
    CancellationToken? cancellation,
  }) async {
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(input)).close();
      await response.pipe(File(output).openWrite());
      return ExportResult(
        output,
        await File(output).length(),
        const Duration(seconds: 1),
      );
    } finally {
      client.close(force: true);
    }
  }
}
