import 'package:zero_player/media/content_filter/optional_resources.dart';
import 'dart:ffi';
import 'package:zero_player/media/content_filter/local_runtime.dart';
import 'package:zero_player/media/content_filter/runtime_catalog.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_capture.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_inspector.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/content_filter/content_filter_service.dart';
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/content_filter/filter_session.dart';
import 'package:zero_player/media/content_filter/local_models.dart';
import 'package:zero_player/media/content_filter/offline_inspector.dart';
import 'package:zero_player/media/content_filter/paddle_ocr.dart';
import 'package:zero_player/media/content_filter/keyword_policy.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import 'package:zero_player/media/gateway/media_gateway.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/media/hls/hls_manifest.dart';

const base = String.fromEnvironment(
  'FIXTURE_BASE',
  defaultValue: 'http://127.0.0.1:9763',
);
const modelPath = String.fromEnvironment('FILTER_MODELS');
const runtimePath = String.fromEnvironment('FILTER_RUNTIME');
late Directory runtime;
late Directory root;
late Directory models;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  setUpAll(_prepare);
  tearDownAll(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  for (final format in ['sample.mp4', 'sample.flv', 'hls/index.m3u8']) {
    testWidgets(
      'model-free capture, offset stripping and playback $format',
      (tester) => _basicPlayback(tester, format),
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
  for (final mode in [FeatureMode.audio, FeatureMode.both]) {
    test(
      'lightweight voice fingerprint ${mode.name}',
      () => _voiceFingerprint(mode),
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
  test(
    'lightweight optional OCR without speech model',
    _ocrOnly,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  _recognitionTests();
  _cueTest();
  testWidgets(
    'approved sliding playlist starts at zero and plays through replenishment',
    _slidingPlayback,
    timeout: const Timeout(Duration(minutes: 8)),
  );
  for (final format in ['sample.mp4', 'sample.flv', 'hls/index.m3u8']) {
    testWidgets(
      'approved features with real models filter and play $format',
      (tester) => _playback(tester, format),
      timeout: const Timeout(Duration(minutes: 8)),
    );
  }
}

Future<void> _voiceFingerprint(FeatureMode mode) async {
  final http = MediaHttpClient(allowPrivateNetworks: true);
  final store = SegmentStore(Directory('${root.path}/voice_cache'));
  await store.initialize();
  final gateway = MediaGateway(store, client: http);
  await gateway.start();
  final transport = gateway.createSession(HeaderPolicy({}));
  final filter = ContentFilterService(
    Directory('${root.path}/voice_filter'),
    http,
    isTrustedInput: gateway.isRegisteredResource,
    isPlaylist: gateway.isRegisteredPlaylist,
  );
  try {
    final input = await transport.openMedia(
      Uri.parse('$base/content_filter/voice.mp4'),
    );
    final rule = await FeatureCapture(filter).capture(
      input,
      sourceId: 'voice',
      originKey: 'voice.mp4',
      from: const Duration(seconds: 4),
      to: const Duration(seconds: 6),
      label: 'voice fixture',
      mode: mode,
      beforeMs: 0,
      afterMs: 6000,
      token: CancellationToken(),
    );
    final session = await filter.create(input, Duration.zero, rules: [rule]);
    await session.begin();
    expect(session.failure, isNull);
    expect(session.status.skipped.inMilliseconds, 8000);
    expect(session.timeline.slices.map((s) => s.originalStart.inSeconds), [
      0,
      12,
    ]);
    expect(await filter.models.directory.exists(), isFalse);
    expect(await filter.resources.runtime.directory.exists(), isFalse);
    debugPrint(
      'AUDIO_FINGERPRINT_NATIVE mode=${mode.name} removedMs=${session.status.skipped.inMilliseconds}',
    );
  } finally {
    transport.close();
    await filter.close();
    await gateway.close();
    http.close();
  }
}

Future<void> _ocrOnly() async {
  final directory = await Directory('${root.path}/ocr_only').create();
  for (final name in ['det.onnx', 'rec.onnx']) {
    await File('${models.path}/$name').copy('${directory.path}/$name');
  }
  final http = MediaHttpClient();
  final inspector = OfflineInspector(
    LocalModels(directory, http),
    runtime: LocalRuntime(runtime, http),
    asr: false,
  );
  try {
    final token = CancellationToken();
    await inspector.prepare(token);
    final decision = await inspector.inspect(
      MediaSlice(
        directory: root,
        media: File('${root.path}/unused.ts'),
        frames: [File('${root.path}/advert.png')],
        audio: null,
        start: Duration.zero,
        duration: const Duration(seconds: 1),
      ),
      token,
    );
    expect(decision.verdict, FilterVerdict.block);
    expect(await File('${directory.path}/speech.onnx').exists(), isFalse);
  } finally {
    await inspector.close();
    http.close();
  }
}

Future<void> _basicPlayback(WidgetTester tester, String format) async {
  final http = MediaHttpClient(allowPrivateNetworks: true);
  final store = SegmentStore(Directory('${root.path}/basic_cache'));
  await store.initialize();
  final gateway = MediaGateway(store, client: http);
  await gateway.start();
  final transport = gateway.createSession(HeaderPolicy({}));
  final filter = ContentFilterService(
    Directory('${root.path}/basic_filter'),
    http,
    isTrustedInput: gateway.isRegisteredResource,
    isPlaylist: gateway.isRegisteredPlaylist,
  );
  final engine = MediaKitEngine(
    isTrustedPlaylist: filter.server.isRegisteredPlaylist,
    isFilteredPlaylist: filter.server.isRegisteredPlaylist,
  );
  try {
    expect(await filter.models.directory.exists(), isFalse);
    expect(await filter.resources.runtime.directory.exists(), isFalse);
    final bundle = File(Platform.resolvedExecutable).parent;
    for (final asset in RuntimePackage.current().files) {
      expect(
        await File('${bundle.path}/${asset.name}').exists(),
        isFalse,
        reason: 'base bundle must not include optional inference libraries',
      );
    }
    final input = await transport.openMedia(
      Uri.parse('$base/content_filter/$format'),
    );
    final rule = await FeatureCapture(filter).capture(
      input,
      sourceId: 'fixture',
      originKey: format,
      from: const Duration(seconds: 4),
      to: const Duration(seconds: 6),
      label: 'synthetic advertising frame',
      mode: FeatureMode.visual,
      beforeMs: 1000,
      afterMs: 7000,
      token: CancellationToken(),
    );
    expect(rule.thumbnail, isNotEmpty);
    final session = await filter.create(input, Duration.zero, rules: [rule]);
    session.changes.listen((e) => debugPrint('BASIC $format: ${e.message}'));
    await session.begin();
    expect(session.failure, isNull);
    expect(session.finished, isTrue);
    expect(session.timeline.slices.map((s) => s.originalStart.inMilliseconds), [
      0,
      13000,
    ]);
    expect(
      session.timeline.duration.inMilliseconds,
      inInclusiveRange(5950, 6150),
    );
    expect(session.status.skipped.inMilliseconds, 10000);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Video(controller: engine.video, controls: NoVideoControls),
        ),
      ),
    );
    await engine.open(filter.server.register(session));
    await engine.video.waitUntilFirstFrameRendered.timeout(
      const Duration(seconds: 25),
    );
    await engine.setRate(2);
    await _until(() => engine.snapshot.position.inMilliseconds >= 3500);
    final image = img.decodeImage(
      Uint8List.fromList((await engine.screenshot())!),
    )!;
    expect(image.getPixel(10, 10).g, greaterThan(image.getPixel(10, 10).r));
    expect(
      session.timeline.originalPosition(engine.snapshot.position).inSeconds,
      greaterThanOrEqualTo(13),
    );
    debugPrint(
      'BASIC_NATIVE_METRIC format=$format removedMs=${session.status.skipped.inMilliseconds} outputMs=${session.timeline.duration.inMilliseconds}',
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await engine.dispose();
    transport.close();
    await filter.close();
    await gateway.close();
    http.close();
  }
}

Future<void> _prepare() async {
  root = await Directory.systemTemp.createTemp('native_content_filter_');
  runtime = Directory(
    runtimePath.isEmpty ? '${root.path}/filter/runtime' : runtimePath,
  );
  if (runtimePath.isEmpty) {
    final http = MediaHttpClient();
    try {
      await LocalRuntime(runtime, http).download(CancellationToken());
    } finally {
      http.close();
    }
  }
  models = Directory('${root.path}/filter/models');
  await models.create(recursive: true);
  for (final asset in LocalModels.assets) {
    final target = File('${models.path}/${asset.name}');
    if (modelPath.isNotEmpty) {
      await File('$modelPath/${asset.name}').copy(target.path);
    } else {
      await _download('$base/content_filter/models/${asset.name}', target);
    }
  }
  for (final name in ['normal.png', 'advert.png', 'speech.wav']) {
    await _download('$base/content_filter/$name', File('${root.path}/$name'));
  }
  final hls = Directory('${root.path}/hls');
  await hls.create();
  for (final name in [
    'index.m3u8',
    'seg_000.ts',
    'seg_001.ts',
    'seg_002.ts',
    'seg_003.ts',
  ]) {
    await _download(
      '$base/content_filter/hls/$name',
      File('${hls.path}/$name'),
    );
  }
}

Future<void> _download(String uri, File file) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(uri))).close();
    if (response.statusCode != 200) {
      throw StateError('Fixture unavailable: $uri');
    }
    await response.pipe(file.openWrite());
  } finally {
    client.close(force: true);
  }
}

void _recognitionTests() {
  test('real OCR evidence requires confirmation before skipping', () async {
    final http = MediaHttpClient();
    final inspector = FeatureInspector(
      const [],
      enhancement: OfflineInspector(
        LocalModels(models, http),
        runtime: LocalRuntime(runtime, http),
        asr: false,
      ),
    );
    final token = CancellationToken();
    try {
      await inspector.prepare(token);
      final decision = await inspector.inspect(
        MediaSlice(
          directory: root,
          media: File('${root.path}/unused.ts'),
          frames: [File('${root.path}/advert.png')],
          audio: null,
          start: const Duration(seconds: 4),
          duration: const Duration(seconds: 4),
        ),
        token,
      );
      expect(decision.verdict, FilterVerdict.block);
      expect(decision.resolvedDetections, isNotEmpty);
      expect(
        decision.resolvedDetections.every((hit) => hit.requiresConfirmation),
        isTrue,
      );
    } finally {
      await inspector.close();
      http.close();
    }
  });
  test('real OCR identifies large Chinese advertisement', () async {
    DynamicLibrary.open(
      '${runtime.path}/${Platform.isWindows ? 'onnxruntime.dll' : 'libonnxruntime.so'}',
    );
    final ocr = PaddleOcr(models.path);
    try {
      final normal = ocr.recognize('${root.path}/normal.png');
      final advert = ocr.recognize('${root.path}/advert.png');
      debugPrint(
        'OCR_AD: ${advert.map((e) => '${e.text}:${e.confidence.toStringAsFixed(3)}').join('|')}',
      );
      expect(const KeywordPolicy().evaluate(normal).allowed, isTrue);
      expect(
        const KeywordPolicy().evaluate(advert).verdict,
        FilterVerdict.block,
      );
    } finally {
      ocr.close();
    }
  });
  test(
    'real offline ASR blocks promotional speech with clean picture',
    () async {
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final inspector = OfflineInspector(
        LocalModels(models, http),
        runtime: LocalRuntime(runtime, http),
      );
      final token = CancellationToken();
      try {
        await inspector.prepare(token);
        final decision = await inspector.inspect(
          MediaSlice(
            directory: root,
            media: File('${root.path}/unused.ts'),
            frames: [File('${root.path}/normal.png')],
            audio: File('${root.path}/speech.wav'),
            start: Duration.zero,
            duration: const Duration(seconds: 12),
          ),
          token,
        );
        debugPrint('ASR_DECISION: ${decision.reason}');
        expect(decision.verdict, FilterVerdict.block);
      } finally {
        await inspector.close();
        http.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _playback(WidgetTester tester, String format) async {
  final http = MediaHttpClient(allowPrivateNetworks: true);
  final store = SegmentStore(Directory('${root.path}/cache'));
  await store.initialize();
  final gateway = MediaGateway(store, client: http);
  await gateway.start();
  final transport = gateway.createSession(HeaderPolicy({}));
  final filter = ContentFilterService(
    Directory('${root.path}/filter'),
    http,
    resources: OptionalResources(
      Directory('${root.path}/filter'),
      http,
      runtime: LocalRuntime(runtime, http),
    ),
    isTrustedInput: gateway.isRegisteredResource,
    isPlaylist: gateway.isRegisteredPlaylist,
  );
  final engine = MediaKitEngine(
    isTrustedPlaylist: filter.server.isRegisteredPlaylist,
    isFilteredPlaylist: filter.server.isRegisteredPlaylist,
  );
  try {
    final input = await transport.openMedia(
      Uri.parse('$base/content_filter/$format'),
    );
    final session = await filter.create(
      input,
      Duration.zero,
      rules: [await _approvedAdvert(filter, input, 4)],
      ocr: true,
      asr: true,
    );
    if (format.startsWith('hls/')) await _diagnoseHls(session.sampler, input);
    session.changes.listen(
      (event) => debugPrint('FILTER $format: ${event.message}'),
    );
    final watch = Stopwatch()..start();
    try {
      await session.begin();
    } catch (_) {
      final probes = await FFprobeKit.listFFprobeSessions();
      if (probes.isNotEmpty) debugPrint(await probes.last.getOutput());
      rethrow;
    }
    expect(session.finished, isTrue);
    expect(session.timeline.slices.map((s) => s.originalStart.inSeconds), [
      0,
      12,
    ]);
    expect(
      session.timeline.duration.inMilliseconds,
      inInclusiveRange(7900, 8150),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Video(controller: engine.video, controls: NoVideoControls),
        ),
      ),
    );
    final subscription = engine.position.listen(session.observe);
    await engine.open(filter.server.register(session));
    await engine.video.waitUntilFirstFrameRendered.timeout(
      const Duration(seconds: 25),
    );
    await engine.setRate(2);
    await _until(() => engine.snapshot.position.inMilliseconds >= 4500);
    final bytes = await engine.screenshot();
    expect(bytes, isNotNull);
    final image = img.decodeImage(Uint8List.fromList(bytes!));
    expect(image, isNotNull);
    final pixel = image!.getPixel(10, 10);
    expect(
      pixel.g,
      greaterThan(pixel.r),
      reason: 'ad red frame reached output',
    );
    expect(
      session.timeline.originalPosition(engine.snapshot.position).inSeconds,
      greaterThanOrEqualTo(12),
    );
    debugPrint(
      'FILTER_NATIVE_METRIC platform=${Platform.operatingSystem} format=$format elapsedMs=${watch.elapsedMilliseconds} removedMs=${session.status.skipped.inMilliseconds}',
    );
    await subscription.cancel();
    await _verifySeek(filter, input);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await engine.dispose();
    transport.close();
    await filter.close();
    await gateway.close();
    http.close();
  }
}

Future<void> _verifySeek(ContentFilterService filter, Uri input) async {
  final session = await filter.create(
    input,
    const Duration(seconds: 12),
    ocr: true,
    asr: true,
  );
  await session.begin();
  expect(
    session.timeline.originalPosition(Duration.zero),
    const Duration(seconds: 12),
  );
  expect(session.timeline.slices.length, 1);
  await filter.release(session);
}

Future<void> _slidingPlayback(WidgetTester tester) async {
  final http = MediaHttpClient(allowPrivateNetworks: true);
  final store = SegmentStore(Directory('${root.path}/long_cache'));
  await store.initialize();
  final gateway = MediaGateway(store, client: http);
  await gateway.start();
  final transport = gateway.createSession(HeaderPolicy({}));
  final filter = ContentFilterService(
    Directory('${root.path}/filter'),
    http,
    resources: OptionalResources(
      Directory('${root.path}/filter'),
      http,
      runtime: LocalRuntime(runtime, http),
    ),
    isTrustedInput: gateway.isRegisteredResource,
    isPlaylist: gateway.isRegisteredPlaylist,
  );
  final engine = MediaKitEngine(
    isTrustedPlaylist: filter.server.isRegisteredPlaylist,
    isFilteredPlaylist: filter.server.isRegisteredPlaylist,
  );
  try {
    final input = await transport.openMedia(
      Uri.parse('$base/content_filter/long.mp4'),
    );
    final session = await filter.create(
      input,
      Duration.zero,
      rules: [await _approvedAdvert(filter, input, 16)],
      ocr: true,
      asr: true,
    );
    await session.begin();
    expect(
      session.finished,
      isFalse,
      reason: 'must exercise a growing playlist',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Video(controller: engine.video, controls: NoVideoControls),
        ),
      ),
    );
    final positions = <Duration>[];
    final subscription = engine.position.listen((position) {
      positions.add(position);
      session.observe(position);
    });
    try {
      await engine.open(filter.server.register(session));
      await engine.video.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 25),
      );
      expect(
        engine.snapshot.position.inMilliseconds,
        lessThan(4000),
        reason: 'growing HLS must not start near its live edge',
      );
      await engine.setRate(2);
      await _until(
        () => engine.snapshot.completed,
        timeout: const Duration(seconds: 100),
      );
      expect(session.failure, isNull);
      expect(session.finished, isTrue);
      expect(session.status.skipped.inSeconds, 8);
      expect(session.timeline.duration.inSeconds, 40);
      expect(session.available.first.sequence, greaterThan(0));
      expect(positions.last.inSeconds, greaterThanOrEqualTo(39));
      expect(
        session.timeline.originalPosition(positions.last).inSeconds,
        greaterThanOrEqualTo(47),
      );
      debugPrint(
        'FILTER_SLIDING_METRIC positionMs=${positions.last.inMilliseconds} '
        'firstAvailable=${session.available.first.sequence}',
      );
    } finally {
      await subscription.cancel();
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await engine.dispose();
    transport.close();
    await filter.close();
    await gateway.close();
    http.close();
  }
}

Future<FeatureRule> _approvedAdvert(
  ContentFilterService filter,
  Uri input,
  int from,
) => FeatureCapture(filter).capture(
  input,
  sourceId: 'approved-fixture',
  originKey: input.path,
  from: Duration(seconds: from),
  to: Duration(seconds: from + 2),
  label: 'explicitly approved advertising fixture',
  mode: FeatureMode.visual,
  beforeMs: 0,
  afterMs: 6000,
  token: CancellationToken(),
);

Future<void> _diagnoseHls(SliceSampler sampler, Uri input) async {
  final token = CancellationToken();
  final length = await sampler.duration(input, token);
  final slice = await sampler.sample(
    input,
    Duration.zero,
    const Duration(seconds: 4),
    Directory('${root.path}/diagnostic'),
    token,
  );
  final ocr = PaddleOcr(models.path);
  try {
    debugPrint('HLS_SOURCE_DURATION ${length.inMilliseconds}');
    for (final frame in slice.frames) {
      final bitmap = img.decodeImage(await frame.readAsBytes())!;
      final pixel = bitmap.getPixel(10, 10);
      expect(
        pixel.g,
        greaterThan(pixel.r),
        reason: 'HLS accurate seek crossed the slice boundary',
      );
      expect(
        const KeywordPolicy().evaluate(ocr.recognize(frame.path)).allowed,
        isTrue,
      );
      debugPrint(
        'HLS_FRAME ${frame.path.split('/').last} R=${pixel.r} G=${pixel.g} TEXT=${ocr.recognize(frame.path).map((e) => e.text).join('|')}',
      );
    }
  } finally {
    ocr.close();
  }
}

Future<void> _until(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > timeout) {
      fail('Playback did not advance');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void _cueTest() {
  testWidgets(
    'declared HLS ad avoids interior segment requests',
    (tester) async {
      final requests = <String>[];
      final server = await _cueSource(requests);
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final store = SegmentStore(Directory('${root.path}/cue_cache'));
      await store.initialize();
      final gateway = MediaGateway(store, client: http);
      await gateway.start();
      final transport = gateway.createSession(HeaderPolicy({}))
        ..filterAds = true;
      final filter = ContentFilterService(
        Directory('${root.path}/filter'),
        http,
        resources: OptionalResources(
          Directory('${root.path}/filter'),
          http,
          runtime: LocalRuntime(runtime, http),
        ),
        isTrustedInput: gateway.isRegisteredResource,
        isPlaylist: gateway.isRegisteredPlaylist,
      );
      try {
        final source = Uri.parse('http://127.0.0.1:${server.port}/index.m3u8');
        final input = await transport.openMedia(source);
        final session = await filter.create(
          input,
          Duration.zero,
          declaredAds: () => transport.timeline.removed,
          ocr: true,
          asr: true,
        );
        await session.begin();
        expect(session.finished, isTrue);
        expect(session.status.skipped.inSeconds, 8);
        expect(session.timeline.slices.map((s) => s.originalStart.inSeconds), [
          0,
          12,
        ]);
        expect(session.timeline.duration.inSeconds, 8);
        expect(requests, isNot(contains('/seg_001.ts')));
        expect(
          requests,
          isNot(contains('/seg_002.ts')),
          reason: 'confirmed interior ad segment must not be downloaded',
        );
        debugPrint('CUE_UPSTREAM_REQUESTS ${requests.join(',')}');
        await _verifyCuePlayback(tester, filter, session);
      } finally {
        transport.close();
        await filter.close();
        await gateway.close();
        http.close();
        await server.close(force: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _verifyCuePlayback(
  WidgetTester tester,
  ContentFilterService filter,
  FilterSession session,
) async {
  final engine = MediaKitEngine(
    isTrustedPlaylist: filter.server.isRegisteredPlaylist,
    isFilteredPlaylist: filter.server.isRegisteredPlaylist,
  );
  final ocr = PaddleOcr(models.path);
  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Video(controller: engine.video, controls: NoVideoControls),
        ),
      ),
    );
    await engine.open(filter.server.register(session));
    await engine.video.waitUntilFirstFrameRendered.timeout(
      const Duration(seconds: 25),
    );
    await engine.setRate(2);
    await _until(() => engine.snapshot.position.inMilliseconds >= 4500);
    final bytes = await engine.screenshot();
    expect(bytes, isNotNull);
    final frame = File('${root.path}/cue-resume.png');
    await frame.writeAsBytes(bytes!);
    final text = ocr.recognize(frame.path).map((e) => e.text).join();
    expect(
      text,
      contains('继续'),
      reason: 'CUE mapping must resume the actual later content',
    );
  } finally {
    ocr.close();
    await tester.pumpWidget(const SizedBox.shrink());
    await engine.dispose();
  }
}

Future<HttpServer> _cueSource(List<String> requests) async {
  final original = HlsManifest.parse(
    await File('${root.path}/hls/index.m3u8').readAsString(),
    Uri.parse('http://example.org/'),
  );
  final lines = <String>[
    '#EXTM3U',
    '#EXT-X-VERSION:3',
    '#EXT-X-TARGETDURATION:4',
  ];
  for (var i = 0; i < original.segments.length; i++) {
    if (i == 1) lines.add('#EXT-X-CUE-OUT:8');
    if (i == 3) lines.add('#EXT-X-CUE-IN');
    final segment = original.segments[i];
    lines.add('#EXTINF:${segment.duration.inMicroseconds / 1e6},');
    lines.add(segment.uri.pathSegments.last);
  }
  lines.add('#EXT-X-ENDLIST');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    requests.add(request.uri.path);
    try {
      if (request.uri.path == '/index.m3u8') {
        request.response.headers.set(
          'content-type',
          'application/vnd.apple.mpegurl',
        );
        request.response.write(lines.join('\n'));
      } else {
        final name = request.uri.pathSegments.last;
        await serveLocalFile(
          request,
          File('${root.path}/hls/$name'),
          contentType: 'video/mp2t',
        );
      }
    } finally {
      await request.response.close();
    }
  });
  return server;
}
