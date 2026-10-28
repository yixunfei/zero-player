import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/downloads/application/download_scheduler.dart';
import 'package:zero_player/features/downloads/domain/download_task.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'resume queues behind an unfinished pause and completes the task',
    _quickResume,
  );
  test(
    'deferred cleanup preserves current task paths and retries orphan paths',
    _cleanup,
  );
  test(
    'download progress does not notify source or settings observers',
    _scopedChanges,
  );
}

Future<void> _quickResume() async {
  final fixture = await _Fixture.create();
  final entered = Completer<void>();
  final release = Completer<void>();
  var attempts = 0;
  final scheduler = DownloadScheduler(
    fixture.services.downloads,
    fixture.services.fetcher,
    fixture.services.http,
    fixture.services.offline,
    fixture.services.settings,
    validateMp4: (_, _) async {},
    resolve: (task, token) async {
      if (attempts++ == 0) {
        entered.complete();
        await release.future;
      }
      return task;
    },
  );
  addTearDown(scheduler.close);
  final id = await fixture.createTask();
  final complete = fixture.services.downloads.changes
      .asyncMap((_) => fixture.services.downloads.find(id))
      .firstWhere((task) => task?.status == DownloadStatus.complete)
      .timeout(const Duration(seconds: 5));
  scheduler.kick();
  await entered.future;
  final pause = scheduler.pause(id);
  final resume = scheduler.resume(id);
  release.complete();
  await Future.wait([pause, resume]);
  expect((await complete)!.status, DownloadStatus.complete);
  expect(attempts, 2);
}

Future<void> _cleanup() async {
  final fixture = await _Fixture.create();
  final repository = fixture.services.downloads;
  final id = await fixture.createTask();
  final current = (await repository.find(id))!.directory;
  final orphan = Directory('${repository.root.path}/old-attempt');
  await orphan.create(recursive: true);
  await File('${orphan.path}/part').writeAsString('unused');
  await repository.deferCleanup(current);
  await repository.deferCleanup(orphan.path);
  await repository.cleanupPending();
  expect(await Directory(current).exists(), isTrue);
  expect(await orphan.exists(), isFalse);
  expect(
    () => repository.deferCleanup(fixture.directory.parent.path),
    throwsStateError,
  );
}

Future<void> _scopedChanges() async {
  final fixture = await _Fixture.create();
  var sourceEvents = 0, downloadEvents = 0;
  final sources = fixture.services.sources.changes.listen(
    (_) => sourceEvents++,
  );
  final downloads = fixture.services.downloads.changes.listen(
    (_) => downloadEvents++,
  );
  addTearDown(sources.cancel);
  addTearDown(downloads.cancel);
  await fixture.services.settings.update({'theme': 'dark'});
  final id = await fixture.createTask();
  await fixture.services.downloads.progress(id, 1, 10, 100);
  await pumpEventQueue();
  expect(sourceEvents, 0);
  expect(downloadEvents, 2);
  await fixture.services.db.atomic(() async {});
  await pumpEventQueue();
  expect(
    sourceEvents,
    1,
    reason: 'global restores still refresh every observer',
  );
}

final class _Fixture {
  _Fixture(this.directory, this.services, this.server);
  final Directory directory;
  final AppServices services;
  final HttpTestServer server;
  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('download-control');
    final services = AppServices.scoped(
      root,
      AppDatabase.memory(),
      allowPrivateNetworks: true,
    );
    await services.settings.load();
    await services.store.initialize();
    final server = await HttpTestServer.start((request) {
      request.response.contentLength = 4;
      request.response.headers.set('content-type', 'video/mp4');
      request.response.add([1, 2, 3, 4]);
    });
    addTearDown(() async {
      await services.close();
      await server.close();
      await root.delete(recursive: true);
    });
    return _Fixture(root, services, server);
  }

  Future<String> createTask() {
    final episode = Episode('1', server.baseUri.resolve('video.mp4'));
    final line = PlayLine('main', [episode]);
    final item = CatalogItem(
      sourceId: 'test',
      id: '1',
      title: 'test',
      lines: [line],
    );
    return services.downloads.create(item, line, episode, {});
  }
}
