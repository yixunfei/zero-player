import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/request_trace.dart';
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
  testWidgets(
    'public music search, native playback and seek through gateway',
    _exerciseMusic,
    skip: !const bool.fromEnvironment('RUN_MUSIC_ONLINE'),
  );
}

MediaKitEngine _createEngine(MediaGateway gateway) {
  final engine = MediaKitEngine(
    videoOutput: false,
    gateway: gateway,
    networkTimeout: const Duration(seconds: 30),
  );
  engine.errors.listen(
    (error) => debugPrint(
      'MUSIC_ENGINE_ERROR '
      '${error.replaceAll(RegExp(r'https?://\S+'), '<media>')}',
    ),
  );
  engine.player.stream.log.listen(
    (log) => debugPrint(
      'MUSIC_NATIVE_LOG '
      '${log.text.replaceAll(RegExp(r'https?://\S+'), '<media>')}',
    ),
  );
  return engine;
}

Future<void> _exerciseMusic(WidgetTester tester) async {
  final root = await Directory.systemTemp.createTemp('music-native-');
  final http = MediaHttpClient();
  final gateway = MediaGateway(SegmentStore(root), client: http);
  final repository = MusicRepository(MyFreeMp3Client(DocumentClient(http)));
  final player = MusicController(repository, () => _createEngine(gateway));
  try {
    final chinese = await repository.search('周杰伦');
    expect(chinese.tracks, isNotEmpty);
    final result = await repository.search('Adele');
    expect(result.tracks, isNotEmpty);
    debugPrint(
      'MUSIC_SEARCH chinese=${chinese.tracks.length} english=${result.tracks.length} hasNext=${result.hasNext}',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MusicPlayer(controller: player)),
      ),
    );
    final trace = <Map<String, Object?>>[];
    await traceRequests(trace, () => player.select(result.tracks, 0));
    debugPrint(
      'MUSIC_OPEN trace=$trace requests=${gateway.requests} failures=${gateway.failures}',
    );
    final watch = Stopwatch()..start();
    while (player.snapshot.position < const Duration(seconds: 1) &&
        watch.elapsed < const Duration(seconds: 25)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint(
      'MUSIC_RESULT trace=$trace requests=${gateway.requests} failures=${gateway.failures}',
    );
    expect(player.error, isNull);
    expect(player.playing, isTrue);
    expect(player.snapshot.position, greaterThan(Duration.zero));
    expect(player.snapshot.duration, greaterThan(const Duration(seconds: 10)));
    expect(gateway.requests, greaterThan(0));
    await player.seek(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(
      player.snapshot.position,
      greaterThanOrEqualTo(const Duration(seconds: 9)),
    );
    await player.pause();
    await tester.pump(const Duration(milliseconds: 200));
    expect(player.playing, isFalse);
    debugPrint(
      'MUSIC_NATIVE_OK gatewayRequests=${gateway.requests} duration=${player.snapshot.duration.inSeconds}',
    );
    await player.stop();
    expect(player.active, isFalse);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await player.close();
    await gateway.close();
    http.close();
    await root.delete(recursive: true);
  }
}
