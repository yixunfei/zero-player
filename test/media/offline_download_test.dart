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
        expect(server.isRegisteredPlaylist(session.uri), isTrue);
        expect(
          server.isRegisteredPlaylist(session.uri.replace(port: 1)),
          isFalse,
        );
        final response = await (await client.getUrl(session.uri)).close();
        final text = await utf8.decoder.bind(response).join();
        final parts = text.split('\n').where((l) => l.endsWith('.ts')).toList();
        final data = await (await client.getUrl(
          session.uri.resolve(parts[1]),
        )).close();
        expect(await data.expand((chunk) => chunk).toList(), [3, 4]);
        session.close();
        expect(server.isPlaying('task'), isFalse);
        expect(server.isRegisteredPlaylist(session.uri), isFalse);
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
  _recoveryTests(job);
  _quotaTests();
  test(
    'failed multi-rendition restart preserves every old local manifest',
    _nestedRevisionTest,
  );
  test('cyclic master references cannot become completed tasks', () async {
    cyclic = true;
    await expectLater(
      job().run(upstream.baseUri.resolve('index.m3u8')),
      throwsFormatException,
    );
  });
}

Future<void> _nestedRevisionTest() async {
  var revision = 0;
  final server = await HttpTestServer.start((request) {
    if (request.uri.path == '/master.m3u8') {
      request.response.write(
        '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="main",DEFAULT=YES,URI="audio.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=100,AUDIO="audio"\nvideo.m3u8\n#revision=$revision\n',
      );
    } else if (request.uri.path.endsWith('.m3u8')) {
      final track = request.uri.path;
      request.response.write(
        '#EXTM3U\n#EXTINF:2,\npart.ts?track=$track&part=1\n#EXTINF:2,\npart.ts?track=$track&part=2\n#EXT-X-ENDLIST\n#revision=$revision\n',
      );
    } else {
      request.response.add([1, 2]);
    }
  });
  addTearDown(server.close);
  HlsDownload job() => HlsDownload(
    id: 'task',
    directory: directory,
    fetcher: SegmentFetcher(store, http),
    http: http,
    policy: HeaderPolicy({}),
    cancellation: CancellationToken(),
    maxBytes: 12,
    onProgress: (_, _, _) async {},
  );
  final uri = server.baseUri.resolve('master.m3u8');
  final entry = await job().run(uri);
  revision++;
  await expectLater(job().run(uri), throwsA(isA<FileSystemException>()));
  final offline = OfflineServer(store);
  addTearDown(offline.close);
  final session = await offline.open('task', directory, entry);
  expect(offline.isPlaying('task'), isTrue);
  session.close();
}

void _quotaTests() {
  HlsDownload limited(int limit, List<int> usage, List<int> reservations) =>
      HlsDownload(
        id: 'task',
        directory: directory,
        fetcher: SegmentFetcher(store, http),
        http: http,
        policy: HeaderPolicy({}),
        cancellation: CancellationToken(),
        maxBytes: limit,
        reserveBytes: reservations.add,
        onProgress: (_, _, bytes) async {
          usage.add(bytes);
        },
      );
  test('same-revision resume counts each existing pin once', () async {
    final uri = upstream.baseUri.resolve('index.m3u8');
    await limited(4, [], []).run(uri);
    final usage = <int>[];
    final reservations = <int>[];
    final resumed = limited(4, usage, reservations);
    await resumed.run(uri);
    expect(usage, everyElement(4));
    expect(reservations, everyElement(4));
    expect(resumed.bytes, 4);
    expect(upstream.calls['/all.ts'], 2);
  });

  test(
    'retained revisions count toward the hard cap even across repeated failures',
    () async {
      final uri = upstream.baseUri.resolve('index.m3u8');
      final entry = await limited(6, [], []).run(uri);
      final original = await File(
        p.join(directory.path, 'resources.json'),
      ).readAsString();
      changed = true;
      final usage = <int>[];
      final reservations = <int>[];
      final restarted = limited(6, usage, reservations);
      await expectLater(
        restarted.run(uri),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'message',
            contains('安全重下需额外空间'),
          ),
        ),
      );
      expect(restarted.bytes, 6);
      expect(usage.last, 6);
      expect(reservations, everyElement(lessThanOrEqualTo(6)));
      expect(
        (await store.pinnedResources(
          'task',
        )).values.fold(0, (sum, bytes) => sum + bytes),
        6,
      );
      expect(
        await File(p.join(directory.path, 'resources.json')).readAsString(),
        original,
      );
      expect(await File(p.join(directory.path, entry)).exists(), isTrue);
      final retry = limited(6, [], []);
      await expectLater(retry.run(uri), throwsA(isA<FileSystemException>()));
      expect(retry.bytes, 6);
      expect(
        (await store.pinnedResources(
          'task',
        )).values.fold(0, (sum, bytes) => sum + bytes),
        6,
      );
    },
  );

  test(
    'successful safe restart reports old plus new usage until retention completes',
    () async {
      final uri = upstream.baseUri.resolve('index.m3u8');
      await limited(8, [], []).run(uri);
      changed = true;
      final usage = <int>[];
      final restarted = limited(8, usage, []);
      await restarted.run(uri);
      expect(usage, containsAllInOrder([4, 6, 8, 4]));
      expect(restarted.bytes, 4);
      expect(
        (await store.pinnedResources(
          'task',
        )).values.fold(0, (sum, bytes) => sum + bytes),
        4,
      );
    },
  );
}

Future<void> _initializeFixture() async {
  directory = await Directory.systemTemp.createTemp('zero-offline-');
  db = AppDatabase.memory();
  http = MediaHttpClient(allowPrivateNetworks: true);
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

void _recoveryTests(HlsDownload Function() job) {
  test(
    'changed manifests restart in an isolated revision without mixing bytes',
    () async {
      await job().run(upstream.baseUri.resolve('index.m3u8'));
      final before =
          jsonDecode(
                await File(
                  p.join(directory.path, 'checkpoints.json'),
                ).readAsString(),
              )
              as Map;
      changed = true;
      await job().run(upstream.baseUri.resolve('index.m3u8'));
      final after =
          jsonDecode(
                await File(
                  p.join(directory.path, 'checkpoints.json'),
                ).readAsString(),
              )
              as Map;
      expect(after['revision'], isNot(before['revision']));
      expect(upstream.calls['/all.ts'], 4);
      final stableRevision = after['revision'];
      await job().run(upstream.baseUri.resolve('index.m3u8'));
      expect(upstream.calls['/all.ts'], 4);
      expect(
        (jsonDecode(
              await File(
                p.join(directory.path, 'checkpoints.json'),
              ).readAsString(),
            )
            as Map)['revision'],
        stableRevision,
      );
    },
  );
  test('offline server can close and reopen the same task', () async {
    final entry = await job().run(upstream.baseUri.resolve('index.m3u8'));
    final server = OfflineServer(store);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });
    await server.open('task', directory, entry);
    await server.close();
    final reopened = await server.open('task', directory, entry);
    final response = await (await client.getUrl(reopened.uri)).close();
    expect(response.statusCode, 200);
    await response.drain<void>();
  });
}
