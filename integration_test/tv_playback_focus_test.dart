import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zero_player/features/playback/presentation/playback_surface.dart';
import 'package:zero_player/features/playback/presentation/player_transport.dart';
import 'package:zero_player/features/playback/presentation/timeline_slider.dart';

import '../test_support/native_mark_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets(
    'TV navigation wakes controls while native media continues playing',
    (tester) async {
      final harness = await NativeMarkHarness.create();
      harness.services.platform.television = true;
      var openedOptions = 0;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
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
                    onOptions: () => openedOptions++,
                    onMark: () {},
                    onScreenshot: () {},
                    onFit: (_) {},
                  ),
                  title: '本地电视焦点测试',
                  onBack: () {},
                  onOptions: () => openedOptions++,
                  locked: false,
                  onLock: (_) {},
                  gestures: true,
                ),
              ),
            ),
          ),
        );
        await harness.open('long.mp4');
        await nativeWidgetUntil(
          tester,
          () => harness.player.originalPosition > const Duration(seconds: 1),
        );
        expect(harness.engine.player.state.width, greaterThan(0));
        await nativeWidgetUntil(
          tester,
          () => find.byTooltip('返回').hitTestable().evaluate().isEmpty,
        );
        final before = harness.player.originalPosition;
        final volume = harness.player.state.volume;
        // Windows has no physical key mapping for the TV Select key.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byTooltip('返回').hitTestable(), findsOneWidget);
        expect(harness.player.state.playing, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 100));
        expect(openedOptions, 1);
        final sliderFocus = tester
            .widget<FocusableActionDetector>(
              find
                  .descendant(
                    of: find.byType(TimelineSlider),
                    matching: find.byType(FocusableActionDetector),
                  )
                  .first,
            )
            .focusNode!;
        sliderFocus.requestFocus();
        await tester.pump(const Duration(milliseconds: 100));
        expect(sliderFocus.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 100));
        expect(sliderFocus.hasPrimaryFocus, isFalse);
        expect(harness.player.state.volume, volume);
        expect(
          harness.player.originalPosition - before,
          lessThan(const Duration(seconds: 5)),
        );
        expect(harness.player.error, isNull);
      } finally {
        await harness.close(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
