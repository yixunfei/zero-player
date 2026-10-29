import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/native_media_commands.dart';
import '../test_support/native_mark_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'content reuse follows history resume, repeated seeks and paused seeks',
    _seekReuse,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<void> _seekReuse(WidgetTester tester) async {
  final h = await NativeMarkHarness.create();
  try {
    await h.mount(tester);
    await _fixture(h, 'mark.mp4', 5000, 40);
    await _fixture(h, 'next.mp4', 303137, 350);
    final item = _series(h.server.port);
    await h.player.open(PlaybackRequest(item));
    await nativeUntil(() => h.player.state.duration > Duration.zero);
    await h.engine.pause();
    final rule = await h.player.captureFeature(
      from: const Duration(seconds: 5),
      to: const Duration(seconds: 21),
      label: '深处广告',
      mode: FeatureMode.audio,
      beforeMs: 0,
      afterMs: 0,
      token: CancellationToken(),
    );
    await h.services.filterFeatures.save(
      rule.copyWith(scope: FeatureScope.series),
    );
    await h.services.settings.update({'contentFilter': true});
    // Enter the NEXT episode inside the ad. No original-episode timestamp shortcut.
    await h.player.open(
      PlaybackRequest(
        item,
        episode: 1,
        position: const Duration(milliseconds: 310500),
      ),
    );
    await _expectSkip(h, 1);
    expect(h.player.activeFeatures.single.originKey, isNot(h.player.workKey));
    // Replay the same content after the matcher and queue already suppressed it.
    await h.engine.pause();
    await nativeUntil(() => !h.player.state.playing);
    await h.player.seek(const Duration(seconds: 301));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(_skipCount(h), 1);
    await h.engine.play();
    await _expectSkip(h, 2);
    // Multiple user changes must end at the newest position, including while paused.
    await h.engine.pause();
    await nativeUntil(() => !h.player.state.playing);
    await Future.wait([
      h.player.seek(const Duration(seconds: 10)),
      h.player.seek(const Duration(seconds: 335)),
      h.player.seek(const Duration(seconds: 309)),
    ]);
    await h.engine.play();
    await _expectSkip(h, 3);
    // Reopen as a different work on the same channel, with history resume.
    await h.services.filterFeatures.save(
      rule.copyWith(scope: FeatureScope.channel),
    );
    await h.player.open(
      PlaybackRequest(
        _series(h.server.port, otherWork: true),
        position: const Duration(seconds: 301),
      ),
    );
    await _expectSkip(h, 4);
    expect(h.player.activeFeatures.single.scope, FeatureScope.channel);
    // ignore: avoid_print
    print(
      'SEEK_REUSE_NATIVE: series resume 310.5s, rewind, paused seek, rapid seeks, channel resume all matched content at 303.137–319.137s',
    );
  } finally {
    // ignore: avoid_print
    print(h.player.diagnosticReport());
    await h.close(tester);
  }
}

int _skipCount(NativeMarkHarness h) =>
    RegExp('跳过 [0-9]+ ->').allMatches(h.player.diagnosticReport()).length;

Future<void> _expectSkip(NativeMarkHarness h, int count) async {
  await nativeUntil(() => _skipCount(h) >= count);
  await nativeUntil(() => h.player.state.position.inMilliseconds >= 318800);
  expect(h.player.state.position.inMilliseconds, lessThan(320500));
  expect(h.player.notice, contains('命中内容特征：深处广告'));
  expect(h.player.notice, isNot(contains('本集标记')));
  expect(h.player.diagnosticReport(), contains('检测跟随跳转至'));
}

Future<void> _fixture(
  NativeMarkHarness h,
  String name,
  int offset,
  int seconds,
) => NativeMediaCommands().run([
  '-stream_loop',
  '-1',
  '-i',
  '$fixtureProject/test_support/generated/content_filter/sample.mp4',
  '-stream_loop',
  '-1',
  '-i',
  '$fixtureProject/test_support/generated/content_filter/speech.wav',
  '-filter_complex',
  '[1:a]atrim=duration=16,asetpts=PTS-STARTPTS,adelay=$offset:all=1,apad[a]',
  '-map',
  '0:v',
  '-map',
  '[a]',
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
  '-t',
  '$seconds',
  '${h.root.path}/$name',
], CancellationToken());

CatalogItem _series(int port, {bool otherWork = false}) => CatalogItem(
  sourceId: 'seek-channel',
  id: otherWork ? 'other-show' : 'show',
  title: otherWork ? '另一部作品' : '跨集续播',
  year: '2026',
  category: '电视剧',
  lines: [
    PlayLine('main', [
      if (!otherWork)
        Episode('1', Uri.parse('http://127.0.0.1:$port/mark.mp4')),
      Episode('2', Uri.parse('http://127.0.0.1:$port/next.mp4')),
    ]),
  ],
);
