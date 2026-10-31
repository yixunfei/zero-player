import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_sample_failure.dart';
import 'package:zero_player/media/content_filter/native_media_commands.dart';
import '../test_support/native_mark_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'unusable audio can save the episode interval and undo',
    _intervalRecovery,
  );
  testWidgets(
    'unusable audio can retry as visual and save a reusable rule',
    _visualRecovery,
  );
  testWidgets(
    '4.5 seconds at 355 seconds, missing and short audio stay bounded',
    _sampleCoverage,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  testWidgets('source changes invalidate an open mark dialog', _sourceChange);
  testWidgets(
    'cancel capture does not persist or stop playback',
    _cancelCapture,
  );
}

Future<void> _sourceChange(WidgetTester tester) async {
  final h = await NativeMarkHarness.create();
  try {
    await _openFailedDialog(tester, h);
    final oldKey = h.player.workKey;
    await h.open('sample.mp4', source: 'other-source');
    await tester.tap(find.text('仅保存本集区间'));
    await nativeWidgetUntil(
      tester,
      () => find.textContaining('视频已切换').evaluate().isNotEmpty,
    );
    expect(await h.services.skips.list(oldKey), isEmpty);
    expect(await h.services.skips.list(h.player.workKey), isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  } finally {
    await h.close(tester);
  }
}

Future<void> _cancelCapture(WidgetTester tester) async {
  final h = await NativeMarkHarness.create();
  try {
    await h.mount(tester);
    await h.open('voice.mp4');
    await h.player.seek(const Duration(seconds: 8));
    await nativeUntil(
      () => h.player.originalPosition >= const Duration(seconds: 8),
    );
    await tester.tap(find.text('标记广告'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final cancel = find.text('取消采集').evaluate().isNotEmpty
        ? find.text('取消采集')
        : find.text('取消');
    await tester.tap(cancel);
    await nativeWidgetUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
    );
    await nativeUntil(
      () => h.player.originalPosition > const Duration(seconds: 9),
    );
    expect(h.engine.snapshot.playing, isTrue);
    expect(await h.services.filterFeatures.list(), isEmpty);
    expect(await h.services.skips.list(h.player.workKey), isEmpty);
    expect(tester.takeException(), isNull);
  } finally {
    await h.close(tester);
  }
}

Future<void> _openFailedDialog(WidgetTester tester, NativeMarkHarness h) async {
  await h.mount(tester);
  await h.open('sample.mp4');
  await h.engine.pause();
  await h.player.seek(const Duration(milliseconds: 8750));
  await nativeUntil(
    () => (h.player.originalPosition.inMilliseconds - 8750).abs() < 200,
  );
  await tester.tap(find.text('标记广告'));
  await nativeWidgetUntil(
    tester,
    () => find.textContaining('声音静音或变化不足').evaluate().isNotEmpty,
  );
  expect(find.textContaining('FormatException'), findsNothing);
  expect(
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '保存并应用'))
        .onPressed,
    isNull,
  );
  expect(
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '仅保存本集区间'))
        .onPressed,
    isNotNull,
  );
  final after = find.widgetWithText(TextField, '向后跳过（0–120 秒）');
  await tester.ensureVisible(after);
  await tester.enterText(after, '4');
  await tester.pump();
}

Future<void> _intervalRecovery(WidgetTester tester) async {
  final h = await NativeMarkHarness.create();
  try {
    await _openFailedDialog(tester, h);
    final position = h.player.originalPosition;
    await tester.tap(find.text('仅保存本集区间'));
    await nativeWidgetUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
    );
    expect(h.engine.snapshot.playing, isFalse);
    expect(
      (h.player.originalPosition - position).abs(),
      lessThan(const Duration(milliseconds: 250)),
    );
    expect(await h.services.filterFeatures.list(), isEmpty);
    final mark = (await h.services.skips.list(h.player.workKey)).single;
    await h.engine.play();
    await nativeUntil(
      () => h.player.canUndoSkip && h.player.originalPosition >= mark.end,
    );
    await h.player.undoSkip();
    await nativeUntil(() => h.player.originalPosition < mark.end);
    expect(h.player.canUndoSkip, isFalse);
    await h.player.seek(mark.start);
    await nativeUntil(
      () => h.player.canUndoSkip && h.player.originalPosition >= mark.end,
    );
    expect(tester.takeException(), isNull);
    // ignore: avoid_print
    print(
      'MARK_INTERVAL_NATIVE failure-to-save=true paused=true undo=true repeat=true',
    );
  } finally {
    await h.close(tester);
  }
}

Future<void> _visualRecovery(WidgetTester tester) async {
  final h = await NativeMarkHarness.create();
  try {
    await _openFailedDialog(tester, h);
    await tester.ensureVisible(find.text('改用画面并采集'));
    await tester.tap(find.text('改用画面并采集'));
    await nativeWidgetUntil(
      tester,
      () => find.textContaining('已提取').evaluate().isNotEmpty,
    );
    expect(find.textContaining('个画面和 0 个音频特征'), findsOneWidget);
    await tester.tap(find.text('保存并应用'));
    await nativeWidgetUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty && !h.player.busy,
    );
    final rule = (await h.services.filterFeatures.list()).single;
    expect(rule.mode, FeatureMode.visual);
    expect(rule.originKey, h.player.workKey);
    expect(h.services.settings.value.contentFilter, isTrue);
    expect(h.engine.snapshot.playing, isFalse);
    await h.engine.play();
    await nativeUntil(() => h.player.canUndoSkip);
    expect(h.player.notice, contains('本集标记'));
    expect(tester.takeException(), isNull);
    // ignore: avoid_print
    print('MARK_VISUAL_NATIVE failure-to-picture=true save=true skip=true');
  } finally {
    await h.close(tester);
  }
}

Future<void> _sampleCoverage(WidgetTester tester) async {
  final h = await NativeMarkHarness.create();
  try {
    await _fixtures(h);
    // ignore: avoid_print
    print('SAMPLE_COVERAGE fixtures ready');
    await h.mount(tester);
    await h.open('long-voice.mp4').timeout(const Duration(seconds: 40));
    // ignore: avoid_print
    print('SAMPLE_COVERAGE long video open');
    await h.engine.pause().timeout(const Duration(seconds: 10));
    // ignore: avoid_print
    print('SAMPLE_COVERAGE paused');
    final voice = await _capture(h, FeatureMode.audio, 355000, 359500);
    // ignore: avoid_print
    print('SAMPLE_COVERAGE long audio captured');
    expect(voice.audio, hasLength(18));
    await h.open('silent.mp4');
    await h.engine.pause();
    await expectLater(
      _capture(h, FeatureMode.audio, 4000, 8500),
      throwsA(
        isA<FeatureSampleFailure>().having(
          (e) => e.issue,
          'issue',
          FeatureSampleIssue.uninformativeAudio,
        ),
      ),
    );
    await h.open('short-audio.mp4');
    await h.engine.pause();
    final partial = await _capture(h, FeatureMode.audio, 4000, 8500);
    expect(partial.sampleMs, 4500);
    expect(partial.signatures.single.durationMs, lessThan(4500));
    expect(partial.signatures.single.durationMs, greaterThanOrEqualTo(1000));
    expect(partial.captureNote, contains('缩短 1 个'));
    await h.open('no-audio.mp4');
    await h.engine.pause();
    await expectLater(
      _capture(h, FeatureMode.audio, 4000, 8500),
      throwsA(isA<Exception>()),
    );
    final picture = await _capture(h, FeatureMode.visual, 4000, 8500);
    expect(picture.visual, hasLength(9));
    expect(picture.audio, isEmpty);
    // ignore: avoid_print
    print(
      'MARK_SAMPLE_NATIVE start=355000 length=4500 frames=18 silent=reject short=observed-only no-audio=visual',
    );
  } finally {
    await h.close(tester);
  }
}

Future<FeatureRule> _capture(
  NativeMarkHarness h,
  FeatureMode mode,
  int start,
  int end,
) => h.player.captureFeature(
  from: Duration(milliseconds: start),
  to: Duration(milliseconds: end),
  label: '采样回归',
  mode: mode,
  beforeMs: 0,
  afterMs: 0,
  token: CancellationToken(),
);

Future<void> _fixtures(NativeMarkHarness h) async {
  final command = NativeMediaCommands();
  final folder = '$fixtureProject/test_support/generated/content_filter';
  await command.run([
    '-stream_loop',
    '-1',
    '-i',
    '$folder/sample.mp4',
    '-i',
    '$folder/speech.wav',
    '-filter_complex',
    '[1:a]atrim=duration=8,asetpts=PTS-STARTPTS,adelay=355000,apad[a]',
    '-map',
    '0:v',
    '-map',
    '[a]',
    '-c:v',
    'copy',
    '-c:a',
    'aac',
    '-t',
    '380',
    '${h.root.path}/long-voice.mp4',
  ], CancellationToken());
  await command.run([
    '-i',
    '$folder/sample.mp4',
    '-c:v',
    'copy',
    '-af',
    'volume=0',
    '-c:a',
    'aac',
    '${h.root.path}/silent.mp4',
  ], CancellationToken());
  await command.run([
    '-i',
    '$folder/voice.mp4',
    '-c:v',
    'copy',
    '-af',
    'atrim=duration=6',
    '-c:a',
    'aac',
    '${h.root.path}/short-audio.mp4',
  ], CancellationToken());
  await command.run([
    '-i',
    '$folder/sample.mp4',
    '-c:v',
    'copy',
    '-an',
    '${h.root.path}/no-audio.mp4',
  ], CancellationToken());
}
