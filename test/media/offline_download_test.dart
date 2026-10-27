import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/persistence/segment_index.dart';
import 'package:zero_player/features/downloads/application/hls_download.dart';
import 'package:zero_player/media/cache/segment_fetcher.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/gateway/offline_server.dart';
import '../../test_support/http_test_server.dart';

late Directory directory;
late AppDatabase db;
late MediaHttpClient http;
late SegmentStore store;
late HttpTestServer upstream;
var cyclic = false;
var changed = false;

void main() {
  setUp(_initializeFixture);
  tearDown(() async {
    http.close();
    await upstream.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  HlsDownload job() => HlsDownload(
    id: 'task',
    directory: directory,
    fetcher: SegmentFetcher(store, http),
    http: http,
    policy: HeaderPolicy({}),
    cancellation: CancellationToken(),
    maxBytes: 100,
    onProgress: (_, total, bytes) async {},
  );
  test(
    'offline ranges become complete resources; durable pins survive cache restart',
    () async {
      final entry = await job().run(upstream.baseUri.resolve('index.m3u8'));
      final manifest = await File(p.join(directory.path, entry)).readAsString();
      expect(manifest, isNot(contains('BYTERANGE')));
      expect(store.sizeBytes, 4);
      expect(store.cacheBytes, 0);
      await store.clearUnused();
      final restored = SegmentStore(
        store.directory,
        metadata: SegmentIndex(db),
      );
      await restored.initialize();
      final server = OfflineServer(restored);
      final client = HttpClient();
      try {
        final session = await server.open('task', directory, entry);
        expect(server.isPlaying('task'), isTrue);
        final response = await (await client.getUrl(session.uri)).close();
        final text = await utf8.decoder.bind(response).join();
        final parts = text.split('\n').where((l) => l.endsWith('.ts')).toList();
        final data = await (await client.getUrl(
          session.uri.resolve(parts[1]),
        )).close();
        expect(await data.expand((chunk) => chunk).toList(), [3, 4]);
        session.close();
        expect(server.isPlaying('task'), isFalse);
        await File(p.join(directory.path, entry)).writeAsString('corrupt');
        await expectLater(
          server.open('task', directory, entry),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        client.close(force: true);
        await server.close();
      }
    },
  );
  test('changed manifests reject unsafe resume', () async {
    await job().run(upstream.baseUri.resolve('index.m3u8'));
    changed = true;
    await expectLater(
      job().run(upstream.baseUri.resolve('index.m3u8')),
      throwsFormatException,
    );
  });
  test('cyclic master references cannot become completed tasks', () async {
    cyclic = true;
    await expectLater(
      job().run(upstream.baseUri.resolve('index.m3u8')),
      throwsFormatException,
    );
  });
}

Future<void> _initializeFixture() async {
  directory = await Directory.systemTemp.createTemp('zero-offline-');
  db = AppDatabase.memory();
  http = MediaHttpClient();
  store = SegmentStore(
    Directory(p.join(directory.path, 'cache')),
    metadata: SegmentIndex(db),
    maxBytes: 10,
  );
  await store.initialize();
  cyclic = false;
  changed = false;
  upstream = await HttpTestServer.start((request) {
    if (request.uri.path.endsWith('.m3u8')) {
      request.response.write(
        cyclic
            ? '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100\nindex.m3u8\n'
            : '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\n#EXT-X-BYTERANGE:2@0\nall.ts\n'
                  '#EXTINF:2,\n#EXT-X-BYTERANGE:2\nall.ts\n#EXT-X-ENDLIST\n${changed ? '#changed\n' : ''}',
      );
    } else {
      final range = request.headers.value('range');
      request.response.statusCode = 206;
      request.response.headers.set(
        'content-range',
        range == 'bytes=0-1' ? 'bytes 0-1/4' : 'bytes 2-3/4',
      );
      request.response.add(range == 'bytes=0-1' ? [1, 2] : [3, 4]);
    }
  });
}
