import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/application/music_browser.dart';
import 'package:zero_player/features/music/application/music_controller.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/music/presentation/music_player.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import 'package:zero_player/media/gateway/media_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  for (final (provider, query, id) in const [
    ('kugou', '理想三旬', '8267B85E29D936AE8FFBA797F64D5B0A'),
    ('netease', '一切为明天 苏芮', '287935'),
  ]) {
    testWidgets(
      '$provider public search and native decoding',
      (tester) => _exerciseSource(tester, provider, query, id),
      skip: !const bool.fromEnvironment('RUN_MUSIC_DIRECT_ONLINE'),
    );
  }
}

Future<void> _exerciseSource(
  WidgetTester tester,
  String provider,
  String query,
  String id,
) async {
  final root = await Directory.systemTemp.createTemp('music-direct-');
  final http = MediaHttpClient();
  final gateway = MediaGateway(SegmentStore(root), client: http);
  final repository = MusicRepository(MyFreeMp3Client(DocumentClient(http)));
  final browser = MusicBrowser(repository);
  final player = MusicController(
    repository,
    () => MediaKitEngine(
      videoOutput: false,
      gateway: gateway,
      networkTimeout: const Duration(seconds: 30),
    ),
  );
  try {
    if (provider == 'kugou') {
      await browser.search(query);
    } else {
      browser.selectProvider(provider);
      await browser.search(query);
    }
    final search = browser.result;
    final index = search.tracks.indexWhere((track) => track.id == id);
    expect(index, greaterThanOrEqualTo(0));
    await player.select(search.tracks, index);
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 25) &&
        player.error == null &&
        (player.snapshot.position < const Duration(seconds: 1) ||
            player.lyricsLoading)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(player.error, isNull);
    expect(player.snapshot.duration, greaterThan(const Duration(seconds: 20)));
    expect(player.snapshot.position, greaterThan(Duration.zero));
    expect(gateway.requests, greaterThan(0));
    if (provider == 'netease') {
      await _checkLyrics(tester, player);
      final list = await repository.importPlaylist(
        '3778678',
        CancellationToken(),
      );
      expect(list.tracks, isNotEmpty);
      expect(list.total, greaterThanOrEqualTo(list.tracks.length));
      expect(list.tracks.every((track) => track.provider == 'netease'), isTrue);
    }
  } finally {
    await browser.close();
    await player.close();
    await gateway.close();
    http.close();
    await root.delete(recursive: true);
  }
}

Future<void> _checkLyrics(WidgetTester tester, MusicController player) async {
  expect(player.lyrics.lines, isNotEmpty);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: MusicPlayer(controller: player)),
    ),
  );
  await tester.tap(find.byTooltip('同步歌词'));
  await tester.pumpAndSettle();
  expect(find.text('同步歌词'), findsOneWidget);
  await player.seek(const Duration(seconds: 35));
  await tester.pump(const Duration(milliseconds: 300));
  final index = player.lyrics.indexAt(player.snapshot.position);
  expect(index, greaterThanOrEqualTo(0));
  final line = player.lyrics.lines[index];
  final text = [
    line.text,
    line.translation,
  ].where((s) => s.isNotEmpty).join('\n');
  expect(text, isNotEmpty);
  expect(find.text(text), findsWidgets);
  await tester.pumpWidget(const SizedBox.shrink());
}
