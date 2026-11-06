import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zero_player/features/playback/presentation/playback_surface.dart';
import 'package:zero_player/features/playback/presentation/player_transport.dart';
import '../test_support/native_mark_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'native playback survives reveal, pause, lock and unlock',
    (tester) async {
      final harness = await NativeMarkHarness.create();
      final boundary = GlobalKey();
      var locked = false;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: StatefulBuilder(
                  builder: (context, update) => ListenableBuilder(
                    listenable: harness.player,
                    builder: (context, _) => PlaybackSurface(
                      controller: harness.player,
                      video: Video(
                        controller: harness.engine.video,
                        controls: NoVideoControls,
                      ),
                      transport: PlayerTransport(
                        controller: harness.player,
                        fullscreen: false,
                        fit: BoxFit.contain,
                        onFullscreen: () {},
                        onOptions: () {},
                        onMark: () {},
                        onScreenshot: () {},
                        onFit: (_) {},
                      ),
                      title: '播放器交互回归',
                      onBack: () {},
                      onOptions: () {},
                      locked: locked,
                      onLock: (value) => update(() => locked = value),
                      gestures: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await harness.open('long.mp4');
        await nativeWidgetUntil(
          tester,
          () => find.byTooltip('返回').hitTestable().evaluate().isEmpty,
        );
        final center = tester.getCenter(find.byType(Video));
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 250));
        expect(harness.player.state.playing, isTrue);
        expect(find.byTooltip('返回').hitTestable(), findsOneWidget);
        await tester.tapAt(center);
        await nativeWidgetUntil(tester, () => !harness.player.state.playing);
        expect(find.text('已暂停'), findsOneWidget);
        await _screenshot(boundary, 'playback-paused.png');
        await tester.tapAt(center);
        await nativeWidgetUntil(tester, () => harness.player.state.playing);
        await tester.tap(find.byTooltip('锁定防误触'));
        await tester.pump(const Duration(seconds: 8));
        expect(find.byTooltip('解除防误触').hitTestable(), findsOneWidget);
        expect(find.byTooltip('返回').hitTestable(), findsNothing);
        final before = harness.player.originalPosition;
        await tester.dragFrom(center, const Offset(120, 0));
        await tester.longPressAt(center);
        await tester.pump(const Duration(seconds: 1));
        expect(harness.player.state.playing, isTrue);
        expect(harness.player.state.rate, 1);
        expect(harness.player.originalPosition, greaterThan(before));
        expect(
          harness.player.originalPosition - before,
          lessThan(const Duration(seconds: 5)),
        );
        await _screenshot(boundary, 'playback-locked.png');
        await tester.tap(find.byTooltip('解除防误触'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(locked, isFalse);
        expect(find.byTooltip('返回').hitTestable(), findsOneWidget);
        expect(harness.player.error, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _screenshot(GlobalKey boundary, String filename) async {
  final render =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final frame = await render.toImage(pixelRatio: 1);
  try {
    final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$fixtureProject/build/$filename',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    frame.dispose();
  }
}
