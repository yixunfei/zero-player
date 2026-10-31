import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/content_filter/keyword_models.dart';
import 'package:zero_player/media/content_filter/local_models.dart';
import 'package:zero_player/media/content_filter/local_runtime.dart';
import 'package:zero_player/media/content_filter/offline_inspector.dart';
import 'package:zero_player/media/content_filter/probe_sampler.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import 'package:zero_player/media/gateway/media_gateway.dart';
import '../test_support/fixture_project.dart';

final project = fixtureProjectRoot();
const base = 'http://127.0.0.1:9763/content_filter';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  for (final format in ['voice.mp4', 'sample.flv', 'hls/index.m3u8']) {
    testWidgets(
      'background audio extraction and original playback $format',
      (tester) => _native(tester, format),
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

Future<void> _native(WidgetTester tester, String format) async {
  final root = await Directory.systemTemp.createTemp('background-native-');
  final http = MediaHttpClient(allowPrivateNetworks: true);
  final store = SegmentStore(Directory('${root.path}/cache'));
  await store.initialize();
  final gateway = MediaGateway(store, client: http);
  await gateway.start();
  final transport = gateway.createSession(HeaderPolicy({}));
  final inspector = OfflineInspector(
    LocalModels(Directory('${root.path}/unused-models'), http),
    runtime: LocalRuntime(
      Directory('$project/.tools/content-filter/runtime'),
      http,
    ),
    keywords: KeywordModels(
      Directory(
        '$project/.tools/content-filter/kws-source/${KeywordModels.prefix}',
      ),
      http,
    ),
    ocr: false,
    asr: false,
    skipSeconds: 10,
  );
  final engine = MediaKitEngine(
    isTrustedResource: gateway.isRegisteredResource,
    isTrustedPlaylist: gateway.isRegisteredPlaylist,
  );
  try {
    final input = await transport.openMedia(Uri.parse('$base/$format'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Video(controller: engine.video, controls: NoVideoControls),
        ),
      ),
    );
    await engine.open(input);
    await inspector.prepare(CancellationToken());
    final sampler = ProbeSampler(
      trusted: gateway.isRegisteredResource,
      playlist: gateway.isRegisteredPlaylist,
      visual: false,
      audio: true,
    );
    final slice = await sampler.sample(
      input,
      const Duration(seconds: 4),
      const Duration(seconds: 4),
      Directory('${root.path}/probe'),
      CancellationToken(),
    );
    expect(slice.frames, isEmpty);
    expect(await slice.media.exists(), isFalse);
    expect(await slice.audio!.length(), greaterThan(1000));
    final decision = await inspector.inspect(slice, CancellationToken());
    if (format == 'voice.mp4') {
      expect(decision.verdict, FilterVerdict.block);
      // A geographic keyword alone must not hide the following strong match.
      expect(decision.reason, contains('新葡京'));
      expect(
        decision.ranges.single.start,
        greaterThan(const Duration(seconds: 4)),
      );
      expect(
        decision.ranges.single.start,
        lessThan(const Duration(seconds: 7)),
      );
      expect(
        decision.ranges.single.end - decision.ranges.single.start,
        const Duration(seconds: 10),
      );
      await engine.seek(const Duration(seconds: 12));
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(engine.snapshot.position, greaterThan(Duration.zero));
    // ignore: avoid_print
    print(
      'BACKGROUND_NATIVE $format position=${engine.snapshot.position} ranges=${decision.ranges.map((r) => r.start.inMilliseconds).toList()}',
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await engine.dispose();
    await inspector.close();
    transport.close();
    await gateway.close();
    http.close();
    await root.delete(recursive: true);
  }
}
