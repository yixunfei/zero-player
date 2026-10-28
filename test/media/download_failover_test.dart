import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/downloads/application/download_failover.dart';
import 'package:zero_player/features/downloads/application/download_scheduler.dart';
import 'package:zero_player/features/downloads/domain/download_task.dart';
import '../../test_support/http_test_server.dart';

late AppServices services;
late Directory root;
late HttpTestServer server;
late DownloadScheduler scheduler;
late String originalId, alternateId;
bool broken = true;

void main() {
  setUp(_setup);
  tearDown(() async {
    await scheduler.close();
    await services.close();
    await server.close();
    await root.delete(recursive: true);
  });
  test(
    'failure switches source and starts a fresh whole-episode directory',
    () async {
      final item = _item('EP1');
      final id = await services.downloads.create(
        item,
        item.lines.first,
        item.lines.first.episodes.first,
        {},
      );
      final oldDirectory = (await services.downloads.find(id))!.directory;
      await File(
        '$oldDirectory/old-source-fragment',
      ).writeAsString('never append me');
      scheduler.kick();
      final completed = await _finished(id);
      expect(
        completed.status,
        DownloadStatus.complete,
        reason: completed.error,
      );
      expect(completed.row['source_id'], alternateId);
      expect(completed.directory, isNot(oldDirectory));
      expect(await Directory(oldDirectory).exists(), isFalse);
      expect(server.calls['/alt-1.ts'], 1);
    },
  );
  test('disabled auto failover never requests another source', () async {
    await services.settings.update({'autoDownloadFallback': false});
    final item = _item('EP1');
    final id = await services.downloads.create(
      item,
      item.lines.first,
      item.lines.first.episodes.first,
      {},
    );
    scheduler.kick();
    final completed = await _finished(id);
    expect(completed.status, DownloadStatus.failed);
    expect(server.calls['/api2'], isNull);
  });
  test(
    'explicit multi-source mode assigns concurrent episodes to distinct sources',
    () async {
      broken = false;
      await services.settings.update({
        'multiSourceDownload': true,
        'downloadConcurrency': 2,
      });
      final ids = <String>[];
      for (final episode in ['EP1', 'EP2']) {
        final item = _item(episode);
        ids.add(
          await services.downloads.create(
            item,
            item.lines.first,
            item.lines.first.episodes.first,
            {},
          ),
        );
      }
      scheduler.kick();
      final completed = await Future.wait(ids.map(_finished));
      expect(
        completed.every((t) => t.status == DownloadStatus.complete),
        isTrue,
      );
      expect(completed.map((t) => t.row['source_id']).toSet(), {
        originalId,
        alternateId,
      });
    },
  );
  _removedSourceTest();
}

CatalogItem _item(String label) => CatalogItem(
  sourceId: originalId,
  id: '1',
  title: '测试剧',
  year: '2026',
  category: '国产剧',
  lines: [
    PlayLine('main', [Episode(label, server.baseUri.resolve('original.m3u8'))]),
  ],
);

Future<DownloadTask> _finished(String id) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    final task = (await services.downloads.find(id))!;
    if ({
      DownloadStatus.complete,
      DownloadStatus.failed,
    }.contains(task.status)) {
      return task;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('Download did not finish');
}

Future<void> _setup() async {
  broken = true;
  root = await Directory.systemTemp.createTemp('zero-failover-');
  services = AppServices.scoped(
    root,
    AppDatabase.memory(),
    allowPrivateNetworks: true,
  );
  await services.supervision.load();
    await services.settings.load();
  await services.store.initialize();
  server = await HttpTestServer.start(_respond);
  originalId = await services.sources.saveManual(
    'original',
    server.baseUri.resolve('api1'),
  );
  alternateId = await services.sources.saveManual(
    'alternate',
    server.baseUri.resolve('api2'),
  );
  scheduler = DownloadScheduler(
    services.downloads,
    services.fetcher,
    services.http,
    services.offline,
    services.settings,
    validateMp4: (_, _) async {},
    failover: DownloadFailover(
      services.sources,
      services.network,
      services.settings,
    ),
  );
}

Future<void> _respond(HttpRequest request) async {
  final path = request.uri.path;
  if (path == '/api2') {
    request.response.write(
      jsonEncode({
        'pagecount': 1,
        'list': [
          {
            'vod_id': '2',
            'vod_name': '测试剧',
            'vod_year': '2026',
            'type_name': '电视剧',
            'vod_play_from': 'alternate',
            'vod_play_url':
                '第01集\$${server.baseUri.resolve('alt-1.m3u8')}#第02集\$${server.baseUri.resolve('alt-2.m3u8')}',
          },
        ],
      }),
    );
  } else if (path == '/original.m3u8' && broken) {
    request.response.statusCode = 404;
  } else if (path.endsWith('.m3u8')) {
    final segment = path.replaceAll('.m3u8', '.ts');
    request.response.write(
      '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\n$segment\n#EXT-X-ENDLIST\n',
    );
  } else if (path.endsWith('.ts')) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    request.response.add(List.filled(188, 71));
  } else {
    request.response.statusCode = 404;
  }
}

void _removedSourceTest() {
  test('removed sources cannot be chosen by download failover', () async {
    await services.sources.suppress(alternateId, true);
    final item = _item('EP1');
    final id = await services.downloads.create(
      item,
      item.lines.first,
      item.lines.first.episodes.first,
      {},
    );
    final location =
        await DownloadFailover(
          services.sources,
          services.network,
          services.settings,
        ).find((await services.downloads.find(id))!, CancellationToken(), {
          originalId,
        });
    expect(location, isNull);
  });
}
