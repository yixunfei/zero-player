import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/application/music_controller.dart';
import 'package:zero_player/features/music/application/music_downloads.dart';
import 'package:zero_player/features/music/data/music_library.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/music/domain/music_track.dart';
import 'package:zero_player/features/music/presentation/music_player.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/cache/segment_fetcher.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import 'package:zero_player/media/export/ffmpeg_exporter.dart';
import 'package:zero_player/media/gateway/media_gateway.dart';
import 'package:zero_player/media/gateway/offline_server.dart';
import '../test_support/http_test_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'audio download validates, reopens offline and records resume history',
    _exercise,
  );
}

Future<void> _exercise(WidgetTester tester) async {
  final root = await Directory.systemTemp.createTemp('music-native-offline-');
  final file = await _audio(root);
  final fixture = await HttpTestServer.start(
    (request) => serveLocalFile(request, file, contentType: 'audio/wav'),
  );
  final db = AppDatabase.memory();
  final http = MediaHttpClient(allowPrivateNetworks: true);
  final store = SegmentStore(Directory('${root.path}/segments'));
  final offline = OfflineServer(store);
  final gateway = MediaGateway(store, client: http);
  final repository = MusicRepository(MyFreeMp3Client(DocumentClient(http)));
  final library = MusicLibrary(db);
  final downloads = MusicDownloads(
    db,
    Directory('${root.path}/downloads'),
    repository,
    http,
    SegmentFetcher(store, http),
    offline,
    validate: FfmpegExporter().validateAudio,
    resolve: (track, token) async => track,
  );
  final track = _track('native', fixture.baseUri.resolve('audio.wav'));
  final second = _track('second', track.url);
  final player = MusicController(
    repository,
    () => MediaKitEngine(
      videoOutput: false,
      gateway: gateway,
      isTrustedResource: offline.isRegisteredResource,
      isTrustedPlaylist: offline.isRegisteredPlaylist,
    ),
    downloadsFactory: () => downloads,
    libraryFactory: () => library,
  );
  try {
    await downloads.download(track);
    await downloads.download(second);
    await downloads.idle;
    expect(downloads.items.every((item) => item.status == 'complete'), isTrue);
    await fixture.close();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MusicPlayer(controller: player)),
      ),
    );
    await player.select([track], 0, start: const Duration(seconds: 3));
    await _wait(
      tester,
      () => player.snapshot.position >= const Duration(seconds: 3),
    );
    expect(player.error, isNull);
    expect(player.playing, isTrue);
    expect(
      gateway.requests,
      0,
      reason: 'offline capabilities must not be re-proxied as upstream URLs',
    );
    await player.pause();
    await tester.pump(const Duration(milliseconds: 200));
    await library.pendingWrites;
    expect(
      library.history.single.position,
      greaterThanOrEqualTo(const Duration(seconds: 3)),
    );
    await _queuePlayback(tester, player, second);
    await library.pendingWrites;
    expect(library.history, hasLength(2));
    await player.stop();
    debugPrint(
      'MUSIC_OFFLINE_NATIVE_OK files=${downloads.items.length} history=${library.history.length} queueAdvance=true',
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await player.close();
    await downloads.close();
    await library.close();
    await offline.close();
    await gateway.close();
    http.close();
    await fixture.close();
    await db.close();
    await root.delete(recursive: true);
  }
}

MusicTrack _track(String id, Uri uri) => MusicTrack(
  id: id,
  title: '离线音频验证 $id',
  artist: 'fixture',
  url: uri,
  fetchedAt: DateTime.now(),
);

Future<void> _queuePlayback(
  WidgetTester tester,
  MusicController player,
  MusicTrack second,
) async {
  await player.enqueue(second, playNext: true);
  await player.seek(
    player.snapshot.duration - const Duration(milliseconds: 300),
  );
  await player.toggle();
  await _wait(
    tester,
    () =>
        player.selected?.key == second.key &&
        player.snapshot.position > Duration.zero,
  );
  expect(player.error, isNull);
  expect(player.playing, isTrue);
  await tester.tap(find.byTooltip('播放队列（2 首）'));
  await tester.pumpAndSettle();
  expect(find.text('播放队列 · 2 首'), findsOneWidget);
  await tester.tap(find.text('清空其他歌曲'));
  await tester.pumpAndSettle();
  expect(player.queue.single.key, second.key);
  await tester.tap(find.text('关闭'));
  await tester.pumpAndSettle();
  await player.pause();
}

Future<void> _wait(WidgetTester tester, bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < const Duration(seconds: 10)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue);
}

Future<File> _audio(Directory root) async {
  const size = 16000 * 12;
  final bytes = Uint8List(44 + size);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, 'RIFF'.codeUnits);
  data.setUint32(4, 36 + size, Endian.little);
  bytes.setAll(8, 'WAVEfmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setAll(36, 'data'.codeUnits);
  data.setUint32(40, size, Endian.little);
  return File('${root.path}/sample.wav').writeAsBytes(bytes);
}
