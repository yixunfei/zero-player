import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/request_scheduler.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/downloads/application/download_scheduler.dart';
import 'package:zero_player/features/downloads/data/download_repository.dart';
import 'package:zero_player/features/downloads/domain/download_task.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';
import 'package:zero_player/media/cache/segment_fetcher.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/gateway/offline_server.dart';

void main() {
  test(
    'pause and close cancel a continuously responding HLS segment and release its permit',
    () async {
      final fixture = await _SlowDownload.create();
      addTearDown(fixture.dispose);
      fixture.scheduler.kick();
      await fixture.waitForChunks(3);
      await fixture.scheduler
          .pause(fixture.id)
          .timeout(const Duration(seconds: 1));
      expect(
        (await fixture.repository.find(fixture.id))!.status,
        DownloadStatus.paused,
      );
      await fixture.expectReleased();

      await fixture.scheduler.resume(fixture.id);
      await fixture.waitForChunks(3, request: 2);
      await fixture.scheduler.close().timeout(const Duration(seconds: 1));
      expect(
        (await fixture.repository.find(fixture.id))!.status,
        DownloadStatus.paused,
      );
      await fixture.expectReleased();
    },
  );
}

final class _SlowDownload {
  _SlowDownload(this.root, this.server, this.db);
  final Directory root;
  final HttpServer server;
  final AppDatabase db;
  final permits = RequestScheduler(globalLimit: 1, originLimit: 1);
  late final http = MediaHttpClient(
    allowPrivateNetworks: true,
    scheduler: permits,
  );
  late final settings = SettingsController(db);
  late final store = SegmentStore(Directory('${root.path}/cache'));
  late final repository = DownloadRepository(
    db,
    Directory('${root.path}/downloads'),
  );
  late final offline = OfflineServer(store);
  late final scheduler = DownloadScheduler(
    repository,
    SegmentFetcher(store, http),
    http,
    offline,
    settings,
    validateMp4: (_, _) async {},
  );
  late final String id;
  int chunks = 0;
  int requests = 0;
  bool closing = false;
  Uri get base => Uri.parse('http://127.0.0.1:${server.port}/');

  static Future<_SlowDownload> create() async {
    final fixture = _SlowDownload(
      await Directory.systemTemp.createTemp('hls-cancellation'),
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      AppDatabase.memory(),
    );
    await fixture.store.initialize();
    fixture.server.listen((request) => unawaited(fixture.respond(request)));
    final item = CatalogItem(
      sourceId: 'test',
      id: 'movie',
      title: 'movie',
      lines: [
        PlayLine('main', [Episode('1', fixture.base.resolve('index.m3u8'))]),
      ],
    );
    fixture.id = await fixture.repository.create(
      item,
      item.lines.single,
      item.lines.single.episodes.single,
      {},
    );
    return fixture;
  }

  Future<void> respond(HttpRequest request) async {
    try {
      if (request.uri.path == '/index.m3u8') {
        request.response.write(
          '#EXTM3U\n#EXTINF:10,\nslow.ts\n#EXT-X-ENDLIST\n',
        );
      } else if (request.uri.path == '/ping') {
        request.response.write('available');
      } else {
        final attempt = ++requests;
        chunks = 0;
        while (!closing) {
          request.response.add(List.filled(1024, 71));
          await request.response.flush();
          if (attempt == requests) chunks++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
    } on IOException {
      // The test deliberately disconnects while the response keeps arriving.
    } on StateError {
      // A disconnected response sink may already be closed.
    } finally {
      try {
        await request.response.close();
      } on IOException {
        /* disconnected */
      } on StateError {
        /* already closed */
      }
    }
  }

  Future<void> waitForChunks(int count, {int request = 1}) => (() async {
    while (requests < request || chunks < count) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  })().timeout(const Duration(seconds: 2));

  Future<void> expectReleased() async {
    final response = await http
        .open(base.resolve('ping'), policy: HeaderPolicy({}))
        .timeout(const Duration(seconds: 1));
    expect(await utf8.decoder.bind(response.body).join(), 'available');
    expect(await store.pinnedResources(id), isEmpty);
    expect(store.sizeBytes, 0);
    expect(
      await store.directory
          .list()
          .where((file) => file.path.endsWith('.part'))
          .toList(),
      isEmpty,
    );
  }

  Future<void> dispose() async {
    closing = true;
    http.close();
    await scheduler.close();
    permits.close();
    await offline.close();
    await server.close(force: true);
    settings.dispose();
    await db.close();
    await root.delete(recursive: true);
  }
}
