import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/media/content_filter/fingerprints/audio_fingerprint.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/native_media_commands.dart';
import 'package:zero_player/media/content_filter/probe_sampler.dart';
import '../test_support/native_mark_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'long marked content survives AAC resampling and shifted episodes',
    _longReuse,
    timeout: const Timeout(Duration(minutes: 5)),
  );
  testWidgets(
    'simultaneous visual output must not truncate decoded audio',
    _dualSampling,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _longReuse(WidgetTester tester) async {
  final h = await NativeMarkHarness.create();
  try {
    await h.mount(tester);
    await _fixtures(h);
    final item = _series(h.server.port);
    await h.player.open(PlaybackRequest(item));
    await nativeUntil(() => h.player.state.duration > Duration.zero);
    await h.engine.pause();
    final rule = await h.player.captureFeature(
      from: const Duration(seconds: 5),
      to: const Duration(seconds: 21),
      label: '长口播完整范围',
      mode: FeatureMode.audio,
      beforeMs: 0,
      afterMs: 0,
      token: CancellationToken(),
    );
    expect(rule.sampleMs, 16000);
    expect(rule.signatures.length, greaterThanOrEqualTo(2));
    await h.services.filterFeatures.save(
      rule.copyWith(scope: FeatureScope.series),
    );
    await h.services.settings.update({'contentFilter': true});
    await h.player.open(PlaybackRequest(item, episode: 1));
    await _expectRelocatedSkip(h);
    await h.services.filterFeatures.save(
      rule.copyWith(scope: FeatureScope.channel),
    );
    await h.open('reused-ad.mp4', source: 'long-source');
    await _expectRelocatedSkip(h);
    expect(h.player.activeFeatures.single.scope, FeatureScope.channel);
    expect(
      Directory('${h.services.contentFilter.root.path}/models').existsSync(),
      isFalse,
    );
    // ignore: avoid_print
    print(
      'LONG_FEATURE_NATIVE 16s selection, shifted 3137ms, AAC 44.1kHz stereo 64k, series and channel passed',
    );
  } finally {
    // ignore: avoid_print
    print(h.player.diagnosticReport());
    await h.close(tester);
  }
}

Future<void> _expectRelocatedSkip(NativeMarkHarness h) async {
  await nativeUntil(() => h.player.canUndoSkip);
  await nativeUntil(() => h.player.originalPosition.inMilliseconds >= 23800);
  expect(h.player.notice, contains('命中内容特征：长口播完整范围'));
  expect(h.player.notice, isNot(contains('本集标记')));
  expect(h.player.originalPosition.inMilliseconds, lessThan(25100));
}

Future<void> _fixtures(NativeMarkHarness h) async {
  const folder = '$fixtureProject/test_support/generated/content_filter';
  final commands = NativeMediaCommands();
  await commands.run([
    '-stream_loop',
    '-1',
    '-i',
    '$folder/sample.mp4',
    '-stream_loop',
    '-1',
    '-i',
    '$folder/speech.wav',
    '-filter_complex',
    '[1:a]atrim=duration=16,asetpts=PTS-STARTPTS,adelay=5000:all=1,apad[a]',
    '-map',
    '0:v',
    '-map',
    '[a]',
    '-c:v',
    'copy',
    '-c:a',
    'aac',
    '-t',
    '45',
    '${h.root.path}/long-ad.mp4',
  ], CancellationToken());
  await commands.run([
    '-i',
    '${h.root.path}/long-ad.mp4',
    '-af',
    'adelay=3137:all=1,volume=0.55',
    '-c:v',
    'copy',
    '-c:a',
    'aac',
    '-ar',
    '44100',
    '-ac',
    '2',
    '-b:a',
    '64k',
    '${h.root.path}/reused-ad.mp4',
  ], CancellationToken());
}

CatalogItem _series(int port) => CatalogItem(
  sourceId: 'long-source',
  id: 'long-series',
  title: '长片段复用',
  year: '2026',
  category: '电视剧',
  lines: [
    PlayLine('main', [
      Episode('1', Uri.parse('http://127.0.0.1:$port/long-ad.mp4')),
      Episode('2', Uri.parse('http://127.0.0.1:$port/reused-ad.mp4')),
    ]),
  ],
);

Future<void> _dualSampling(WidgetTester tester) async {
  final h = await NativeMarkHarness.create();
  try {
    final input = Uri.parse('http://127.0.0.1:${h.server.port}/voice.mp4');
    final old = Directory('${h.root.path}/old-probe');
    await old.create();
    await NativeMediaCommands().run([
      '-threads',
      '1',
      '-ss',
      '4',
      '-i',
      input.toString(),
      '-t',
      '4',
      '-map',
      '0:v:0',
      '-an',
      '-sn',
      '-dn',
      '-vf',
      'fps=2,scale=640:-2',
      '-frames:v',
      '8',
      '-threads',
      '1',
      '${old.path}/frame_%03d.jpg',
      '-t',
      '4',
      '-map',
      '0:a:0',
      '-vn',
      '-sn',
      '-dn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-c:a',
      'pcm_s16le',
      '-threads',
      '1',
      '${old.path}/audio.wav',
    ], CancellationToken());
    final oldMs =
        readPcmWave(await File('${old.path}/audio.wav').readAsBytes()).length /
        16;
    final sampler = ProbeSampler(
      trusted: (_) => true,
      playlist: (_) => false,
      visual: true,
      audio: true,
    );
    final fixed = await sampler.sample(
      input,
      const Duration(seconds: 4),
      const Duration(seconds: 4),
      Directory('${h.root.path}/fixed'),
      CancellationToken(),
    );
    final newMs = readPcmWave(await fixed.audio!.readAsBytes()).length / 16;
    expect(newMs, greaterThanOrEqualTo(3990));
    expect(fixed.frames.length, greaterThanOrEqualTo(8));
    // ignore: avoid_print
    print(
      'DUAL_SAMPLING_NATIVE previous_audio_ms=$oldMs fixed_audio_ms=$newMs',
    );
  } finally {
    await h.close(tester);
  }
}
