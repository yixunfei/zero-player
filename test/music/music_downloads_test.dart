import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/application/music_downloads.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/music/domain/music_track.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/cache/segment_fetcher.dart';
import 'package:zero_player/media/gateway/offline_server.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'local search indexes complete downloads across restart and removes stale entries',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.close);
      await f.downloads.download(f.track);
      await f.downloads.idle;
      expect(f.downloads.searchLocal('离线 TEST').single.key, f.track.key);
      expect(f.downloads.searchLocal('other'), isEmpty);
      expect(f.downloads.searchLocal('  '), isEmpty);
      expect(f.downloads.completed(f.track)?.status, 'complete');
      MusicTrack remote({
        Duration duration = Duration.zero,
        String title = '离线测试',
      }) => MusicTrack(
        id: 'remote',
        title: title,
        artist: 'TEST',
        url: f.track.url,
        provider: 'netease',
        duration: duration,
        fetchedAt: DateTime.now(),
      );
      expect(f.downloads.localFor(remote())?.track.key, f.track.key);
      expect(f.downloads.localFor(remote(title: '离线测试 Live')), isNull);
      await f.downloads.close();
      f.downloads = f.createDownloads();
      await f.downloads.load();
      expect(f.downloads.searchLocal('离线').single.key, f.track.key);
      final local = await f.downloads.open(f.track);
      expect(local, isNotNull);
      local!.close();
      await f.downloads.remove(f.track);
      expect(f.downloads.completed(f.track), isNull);
      expect(f.downloads.searchLocal('离线'), isEmpty);
    },
  );
  _recoveryTests();
  _downloadTests();
  _queueTests();
  _quotaResumeTests();
}

MusicTrack _other(_Fixture f, String id) => MusicTrack(
  id: id,
  title: id,
  artist: '',
  url: f.track.url,
  fetchedAt: DateTime.now(),
);

void _queueTests() {
  test(
    'queued pause and removal finish without waiting for another download; replacement is not lost',
    () async {
      final f = await _Fixture.create();
      final entered = Completer<void>(), release = Completer<void>();
      f.resolver = (track, token) async {
        if (track.id == f.track.id) {
          entered.complete();
          await release.future;
        }
        return track;
      };
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await f.close();
      });
      final paused = _other(f, 'paused'), removed = _other(f, 'removed');
      await f.downloads.download(f.track);
      await entered.future;
      await f.downloads.download(paused);
      await f.downloads.download(removed);
      await f.downloads.pause(paused).timeout(const Duration(seconds: 1));
      await f.downloads.remove(removed).timeout(const Duration(seconds: 1));
      await f.downloads.download(paused);
      await f.downloads.download(paused);
      release.complete();
      await f.downloads.idle;
      expect(f.downloads.items, hasLength(2));
      expect(
        f.downloads.items.every((item) => item.status == 'complete'),
        isTrue,
      );
      expect(f.server.calls['/audio.wav'], 2);
      expect(await f.downloads.directory(removed).exists(), isFalse);
    },
  );
  test(
    'pausing an active task does not wait for a later queued task',
    () async {
      final f = await _Fixture.create();
      final entered = Completer<void>(),
          release = Completer<void>(),
          otherRelease = Completer<void>();
      f.resolver = (track, token) async {
        if (track.id == f.track.id) {
          entered.complete();
          final unlink = token.listen(() {
            if (!release.isCompleted) release.complete();
          });
          try {
            await release.future;
            token.check();
          } finally {
            unlink();
          }
        } else {
          await otherRelease.future;
        }
        return track;
      };
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        if (!otherRelease.isCompleted) otherRelease.complete();
        await f.close();
      });
      await f.downloads.download(f.track);
      await entered.future;
      await f.downloads.download(_other(f, 'later'));
      await f.downloads.pause(f.track).timeout(const Duration(seconds: 1));
      expect(
        f.downloads.items.firstWhere((i) => i.track.key == f.track.key).status,
        'paused',
      );
      otherRelease.complete();
      await f.downloads.idle;
      expect(
        f.downloads.items.firstWhere((i) => i.track.id == 'later').status,
        'complete',
      );
    },
  );
}

void _quotaResumeTests() {
  for (final otherBytes in [0, 5000]) {
    test(
      'resume counts retained partial bytes once with $otherBytes bytes of other files',
      () async {
        final f = await _Fixture.create(limit: 10000, total: 10000);
        addTearDown(f.close);
        final dir = f.downloads.directory(f.track);
        await dir.create(recursive: true);
        await File(
          '${dir.path}/audio.wav.part',
        ).writeAsBytes((await f.audio.readAsBytes()).take(4096).toList());
        await File('${dir.path}/mp4-state.json').writeAsString(
          jsonEncode({
            'uri': f.track.url.toString(),
            'etag': '"music-fixture"',
            'total': 8044,
          }),
        );
        if (otherBytes > 0) {
          await File(
            '${dir.parent.path}/other.keep',
          ).writeAsBytes(List.filled(otherBytes, 0));
        }
        await f.downloads.download(f.track);
        await f.downloads.idle;
        expect(
          f.downloads.items.single.status,
          otherBytes == 0 ? 'complete' : 'failed',
        );
        expect(f.ranges, ['bytes=4096-']);
        var retained = 0;
        await for (final file in f.downloads.root.list(recursive: true)) {
          if (file is File) retained += await file.length();
        }
        expect(retained, lessThanOrEqualTo(10000));
      },
    );
  }
}

void _recoveryTests() {
  test(
    'interrupted task recovery stays paused after later updates and can resume',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.db.write('INSERT INTO app_meta VALUES(?,?)', [
        'music_download:${fixture.downloads.id(fixture.track)}',
        jsonEncode({
          'track': fixture.track.toJson(),
          'status': 'downloading',
          'bytes': 0,
          'entry': null,
          'error': null,
        }),
      ]);
      await fixture.downloads.load();
      expect(fixture.downloads.items.single.status, 'paused');
      final other = MusicTrack(
        id: 'other',
        title: 'other',
        artist: '',
        url: fixture.track.url,
        fetchedAt: DateTime.now(),
      );
      await fixture.downloads.download(other);
      await fixture.downloads.idle;
      expect(
        fixture.downloads.items
            .firstWhere((i) => i.track.key == fixture.track.key)
            .status,
        'paused',
      );
      await fixture.downloads.download(fixture.track);
      await fixture.downloads.idle;
      expect(
        fixture.downloads.items.every((i) => i.status == 'complete'),
        isTrue,
      );
    },
  );
}

void _downloadTests() {
  test(
    'download is verified, works offline after restart, rejects tampering and protects active files',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.downloads.download(fixture.track);
      await fixture.downloads.idle;
      expect(fixture.downloads.items.single.status, 'complete');
      expect(fixture.server.calls['/audio.wav'], 1);
      await fixture.downloads.close();
      fixture.downloads = fixture.createDownloads();
      final session = await fixture.downloads.open(fixture.track);
      expect(session, isNotNull);
      final client = HttpClient();
      final request = await client.getUrl(session!.uri);
      final response = await request.close();
      final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      client.close(force: true);
      expect(bytes.length, fixture.audio.lengthSync());
      expect(
        fixture.server.calls['/audio.wav'],
        1,
        reason: 'offline playback must not access origin',
      );
      await expectLater(
        fixture.downloads.remove(fixture.track),
        throwsFormatException,
      );
      session.close();
      final item = fixture.downloads.items.single;
      await File(
        '${fixture.downloads.directory(fixture.track).path}/${item.entry}',
      ).writeAsString('tampered');
      await expectLater(
        fixture.downloads.open(fixture.track),
        throwsA(isA<FileSystemException>()),
      );
      await fixture.downloads.remove(fixture.track);
      expect(fixture.downloads.items, isEmpty);
    },
  );
  test(
    'capacity limits fail safely and a non-downloadable source is rejected',
    () async {
      final fixture = await _Fixture.create(limit: 64);
      addTearDown(fixture.close);
      await fixture.downloads.download(fixture.track);
      await fixture.downloads.idle;
      expect(fixture.downloads.items.single.status, 'failed');
      expect(await fixture.downloads.open(fixture.track), isNull);
      final blocked = MusicTrack(
        id: 'blocked',
        title: 'blocked',
        artist: '',
        url: fixture.track.url,
        fetchedAt: DateTime.now(),
        downloadable: false,
      );
      await expectLater(
        fixture.downloads.download(blocked),
        throwsFormatException,
      );
      for (final provider in ['qqmp3', 'lxHyw']) {
        await expectLater(
          fixture.downloads.download(
            MusicTrack(
              id: 'restricted',
              title: 'restricted',
              artist: '',
              url: fixture.track.url,
              fetchedAt: DateTime.now(),
              provider: provider,
              downloadable: true,
            ),
          ),
          throwsFormatException,
        );
      }
    },
  );
}

final class _Fixture {
  late Directory root;
  late File audio;
  late HttpTestServer server;
  final db = AppDatabase.memory();
  final http = MediaHttpClient(allowPrivateNetworks: true);
  late SegmentStore store;
  late OfflineServer offline;
  late MusicRepository repository;
  late MusicTrack track;
  late MusicDownloads downloads;
  int limit = 1024 * 1024;
  int total = 1024 * 1024 * 1024;
  final ranges = <String?>[];
  Future<MusicTrack> Function(MusicTrack, CancellationToken)? resolver;
  static Future<_Fixture> create({
    int limit = 1024 * 1024,
    int total = 1024 * 1024 * 1024,
  }) async {
    final fixture = _Fixture()
      ..limit = limit
      ..total = total;
    fixture.root = await Directory.systemTemp.createTemp('music-offline-');
    fixture.audio = File('${fixture.root.path}/input.wav');
    final bytes = Uint8List(8044);
    final data = ByteData.sublistView(bytes);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes[offset + i] = value.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 8036, Endian.little);
    ascii(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, 8000, Endian.little);
    data.setUint32(28, 16000, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, 8000, Endian.little);
    await fixture.audio.writeAsBytes(bytes);
    fixture.server = await HttpTestServer.start((request) {
      fixture.ranges.add(request.headers.value('range'));
      request.response.headers.set('etag', '"music-fixture"');
      return serveLocalFile(request, fixture.audio, contentType: 'audio/wav');
    });
    fixture.store = SegmentStore(Directory('${fixture.root.path}/segments'));
    fixture.offline = OfflineServer(fixture.store);
    fixture.repository = MusicRepository(
      MyFreeMp3Client(DocumentClient(fixture.http)),
    );
    fixture.track = MusicTrack(
      id: 'fixture',
      title: '离线测试',
      artist: 'test',
      url: fixture.server.baseUri.resolve('audio.wav'),
      fetchedAt: DateTime.now(),
    );
    fixture.downloads = fixture.createDownloads();
    return fixture;
  }

  MusicDownloads createDownloads() => MusicDownloads(
    db,
    Directory('${root.path}/downloads'),
    repository,
    http,
    SegmentFetcher(store, http),
    offline,
    maxBytes: limit,
    totalBytes: total,
    resolve: (track, token) async =>
        await resolver?.call(track, token) ?? track,
    validate: (file, token) async {
      expect(await file.length(), await audio.length());
    },
  );
  Future<void> close() async {
    await downloads.close();
    await offline.close();
    http.close();
    await server.close();
    await db.close();
    await root.delete(recursive: true);
  }
}
