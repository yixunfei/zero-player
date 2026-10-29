import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/native_media_commands.dart';
import '../test_support/native_mark_harness.dart';
import 'package:zero_player/features/playback/presentation/feature_rule_dialog.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'local audio rule matches a shifted next episode and confirms a later visit',
    _crossEpisode,
    timeout: const Timeout(Duration(minutes: 4)),
  );
  testWidgets(
    're-extraction replaces the original sample and preserves disabled state',
    _reextract,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _crossEpisode(WidgetTester tester) async {
  final h = await NativeMarkHarness.create();
  try {
    await h.mount(tester);
    await _shiftedFixture(h);
    final item = _series(h.server.port);
    await h.player.open(PlaybackRequest(item));
    await nativeUntil(() => h.player.state.duration > Duration.zero);
    final captured = await h.player.captureFeature(
      from: const Duration(seconds: 4),
      to: const Duration(milliseconds: 8500),
      label: '跨集口播',
      mode: FeatureMode.audio,
      beforeMs: 0,
      afterMs: 5500,
      token: CancellationToken(),
    );
    await h.services.filterFeatures.save(
      captured.copyWith(scope: FeatureScope.series),
    );
    await h.services.settings.update({'contentFilter': true});
    await h.player.open(PlaybackRequest(item, episode: 1));
    await nativeUntil(() => h.player.canUndoSkip);
    await nativeUntil(() => h.player.originalPosition.inMilliseconds > 16000);
    expect(h.player.notice, contains('命中内容特征：跨集口播'));
    expect(h.player.notice, isNot(contains('本集标记')));
    expect(h.player.originalPosition.inMilliseconds, greaterThan(16000));
    expect(h.player.activeFeatures.single.scope, FeatureScope.series);
    await h.services.settings.update({'filterStrategy': 'confirm'});
    await h.player.open(PlaybackRequest(item, episode: 1));
    await nativeUntil(() => h.player.pendingFeature != null);
    expect(h.player.canUndoSkip, isFalse);
    h.player.confirmFeatureSkip();
    await nativeUntil(() => h.player.canUndoSkip);
    await nativeUntil(() => h.player.originalPosition.inMilliseconds > 16000);
    await h.player.undoSkip();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(h.player.pendingFeature, isNull);
    expect(h.player.canUndoSkip, isFalse);
    expect(
      Directory('${h.services.contentFilter.root.path}/models').existsSync(),
      isFalse,
    );
    // ignore: avoid_print
    print(
      'FEATURE_REUSE_NATIVE shifted=3137ms cross-episode=true confirm=true models=false',
    );
  } finally {
    // ignore: avoid_print
    print(h.player.diagnosticReport());
    await h.close(tester);
  }
}

Future<void> _shiftedFixture(NativeMarkHarness h) => NativeMediaCommands().run([
  '-i',
  '$fixtureProject/test_support/generated/content_filter/voice.mp4',
  '-af',
  'adelay=3137:all=1',
  '-c:v',
  'copy',
  '-c:a',
  'aac',
  '${h.root.path}/shifted.mp4',
], CancellationToken());

CatalogItem _series(int port) => CatalogItem(
  sourceId: 'reusable-source',
  id: 'series',
  title: '内容错位测试',
  year: '2026',
  category: '电视剧',
  lines: [
    PlayLine('main', [
      Episode('1', Uri.parse('http://127.0.0.1:$port/voice.mp4')),
      Episode('2', Uri.parse('http://127.0.0.1:$port/shifted.mp4')),
    ]),
  ],
);

Future<void> _reextract(WidgetTester tester) async {
  final h = await NativeMarkHarness.create();
  try {
    await h.mount(tester);
    await h.open('voice.mp4');
    await h.engine.pause();
    final captured = await h.player.captureFeature(
      from: const Duration(seconds: 4),
      to: const Duration(milliseconds: 8500),
      label: '重新采集',
      mode: FeatureMode.audio,
      beforeMs: 0,
      afterMs: 20000,
      token: CancellationToken(),
    );
    final saved = captured.copyWith(scope: FeatureScope.series, enabled: false);
    await h.services.filterFeatures.save(saved);
    await h.player.seek(const Duration(seconds: 8));
    await nativeUntil(
      () => (h.player.originalPosition.inMilliseconds - 8000).abs() < 100,
    );
    final editing = editFeatureRule(
      tester.element(find.text('标记广告')),
      h.player,
      rule: saved,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('从当前视频重新提取'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('采集并预览'));
    await nativeWidgetUntil(
      tester,
      () =>
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '保存并应用'))
              .onPressed !=
          null,
    );
    await tester.tap(find.text('保存并应用'));
    await nativeWidgetUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
    );
    await editing;
    final updated = (await h.services.filterFeatures.list()).single;
    expect(updated.id, saved.id);
    expect(updated.enabled, isFalse);
    expect(updated.scope, FeatureScope.series);
    expect(updated.sampleMs, 4000);
    expect(updated.audio.length, 16);
    expect(tester.takeException(), isNull);
  } finally {
    await h.close(tester);
  }
}
