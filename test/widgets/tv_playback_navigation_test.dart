import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import 'package:zero_player/features/playback/presentation/playback_surface.dart';
import 'package:zero_player/features/playback/presentation/player_transport.dart';
import 'package:zero_player/features/playback/presentation/timeline_slider.dart';

import '../../test_support/fake_player_engine.dart';

late Directory root;
late AppServices services;
late FakePlayerEngine engine;
late PlaybackController controller;

void main() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tv-playback-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.settings.load();
    services.platform.television = true;
    engine = FakePlayerEngine();
    controller = PlaybackController(services, engine);
    engine.snapshot = const PlaybackSnapshot(
      position: Duration(seconds: 12),
      duration: Duration(minutes: 2),
      playing: true,
      volume: 60,
    );
    controller.state = engine.snapshot;
  });

  tearDown(() async {
    await controller.close();
    await services.close();
    await root.delete(recursive: true);
  });

  _visibleAndHiddenTests();
  _confirmAndLockTests();
  _controlAndTimelineTests();
  _volumeTests();
  _desktopTests();
  _phoneAndDialogTests();
}

void _visibleAndHiddenTests() {
  testWidgets(
    'TV direction keys focus visible controls without changing media',
    (tester) async {
      var back = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaybackSurface(
              controller: controller,
              video: const ColoredBox(color: Colors.black),
              transport: TextButton(
                onPressed: () {},
                child: const Text('播放控制'),
              ),
              title: 'movie',
              onBack: () => back++,
              onOptions: () {},
              locked: false,
              onLock: (_) {},
              gestures: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(engine.snapshot.volume, 60);
      expect(engine.seeks, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(back, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('TV direction keys wake hidden controls before seeking', (
    tester,
  ) async {
    var back = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackSurface(
            controller: controller,
            video: const ColoredBox(color: Colors.black),
            transport: const Text('播放控制'),
            title: 'movie',
            onBack: () => back++,
            onOptions: () {},
            locked: false,
            onLock: (_) {},
            gestures: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('返回').hitTestable(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.seeks, isEmpty);
    expect(find.byTooltip('返回').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(back, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _confirmAndLockTests() {
  testWidgets('TV confirm wakes hidden controls without pausing playback', (
    tester,
  ) async {
    var back = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackSurface(
            controller: controller,
            video: const ColoredBox(color: Colors.black),
            transport: const Text('播放控制'),
            title: 'movie',
            onBack: () => back++,
            onOptions: () {},
            locked: false,
            onLock: (_) {},
            gestures: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(engine.snapshot.playing, isTrue);
    expect(back, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(back, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TV remote can reveal and unlock hidden controls', (
    tester,
  ) async {
    var locked = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PlaybackSurface(
              controller: controller,
              video: const ColoredBox(color: Colors.black),
              transport: const Text('播放控制'),
              title: 'movie',
              onBack: () {},
              onOptions: () {},
              locked: locked,
              onLock: (value) => setState(() => locked = value),
              gestures: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('解除防误触'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byTooltip('解除防误触').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(locked, isFalse);
    expect(engine.snapshot.volume, 60);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _controlAndTimelineTests() {
  testWidgets('TV focus can reach settings and keeps controls visible', (
    tester,
  ) async {
    var options = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackSurface(
            controller: controller,
            video: const ColoredBox(color: Colors.black),
            transport: TextButton(onPressed: () {}, child: const Text('播放控制')),
            title: 'movie',
            onBack: () {},
            onOptions: () => options++,
            locked: false,
            onLock: (_) {},
            gestures: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('选集与播放设置').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(options, 1);
    expect(engine.snapshot.playing, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TV can adjust and leave the timeline with direction keys', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackSurface(
            controller: controller,
            video: const ColoredBox(color: Colors.black),
            transport: PlayerTransport(
              controller: controller,
              fullscreen: false,
              fit: BoxFit.contain,
              onFullscreen: () {},
              onOptions: () {},
              onMark: () {},
              onScreenshot: () {},
              onFit: (_) {},
            ),
            title: 'movie',
            onBack: () {},
            onOptions: () {},
            locked: false,
            onLock: (_) {},
            gestures: true,
          ),
        ),
      ),
    );
    await tester.pump();
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
    await tester.pump();
    expect(sliderFocus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.seeks, isNotEmpty);
    final seeksAfterAdjustment = engine.seeks.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(engine.seeks, hasLength(seeksAfterAdjustment));
    expect(sliderFocus.hasPrimaryFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(sliderFocus.hasPrimaryFocus, isTrue);
    expect(engine.seeks, hasLength(seeksAfterAdjustment));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _volumeTests() {
  testWidgets('TV volume slider leaves vertical keys for navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackSurface(
            controller: controller,
            video: const ColoredBox(color: Colors.black),
            transport: PlayerTransport(
              controller: controller,
              fullscreen: false,
              fit: BoxFit.contain,
              onFullscreen: () {},
              onOptions: () {},
              onMark: () {},
              onScreenshot: () {},
              onFit: (_) {},
            ),
            title: 'movie',
            onBack: () {},
            onOptions: () {},
            locked: false,
            onLock: (_) {},
            gestures: true,
          ),
        ),
      ),
    );
    await tester.pump();
    final slider = find.byType(Slider).last;
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final sliderFocus = tester
        .widget<FocusableActionDetector>(
          find
              .descendant(
                of: slider,
                matching: find.byType(FocusableActionDetector),
              )
              .first,
        )
        .focusNode!;
    sliderFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final adjustedVolume = engine.snapshot.volume;
    expect(adjustedVolume, greaterThan(60));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(engine.snapshot.volume, adjustedVolume);
    expect(sliderFocus.hasPrimaryFocus, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _desktopTests() {
  testWidgets('TV display preference enables remote navigation on desktop', (
    tester,
  ) async {
    services.platform.television = false;
    await tester.runAsync(
      () => services.settings.update({'mode': 'television'}),
    );
    var back = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackSurface(
            controller: controller,
            video: const ColoredBox(color: Colors.black),
            transport: const Text('播放控制'),
            title: 'movie',
            onBack: () => back++,
            onOptions: () {},
            locked: false,
            onLock: (_) {},
            gestures: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(back, 1);
    expect(engine.snapshot.volume, 60);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'desktop keyboard can return to the video after visiting controls',
    (tester) async {
      services.platform.television = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaybackSurface(
              controller: controller,
              video: const ColoredBox(color: Colors.black),
              transport: const Text('播放控制'),
              title: 'movie',
              onBack: () {},
              onOptions: () {},
              locked: false,
              onLock: (_) {},
              gestures: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(engine.seeks, [const Duration(seconds: 22)]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

void _phoneAndDialogTests() {
  testWidgets(
    'landscape phone keeps keyboard shortcuts with TV preference',
    (tester) async {
      services.platform.television = false;
      await tester.runAsync(
        () => services.settings.update({'mode': 'television'}),
      );
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaybackSurface(
              controller: controller,
              video: const ColoredBox(color: Colors.black),
              transport: const Text('播放控制'),
              title: 'movie',
              onBack: () {},
              onOptions: () {},
              locked: false,
              onLock: (_) {},
              gestures: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(engine.seeks, [const Duration(seconds: 22)]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets('an open dialog keeps focus when player controls time out', (
    tester,
  ) async {
    services.platform.television = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => PlaybackSurface(
              controller: controller,
              video: const ColoredBox(color: Colors.black),
              transport: const Text('播放控制'),
              title: 'movie',
              onBack: () {},
              onOptions: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    const AlertDialog(content: TextField(autofocus: true)),
              ),
              locked: false,
              onLock: (_) {},
              gestures: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('选集与播放设置'));
    await tester.pumpAndSettle();
    final input = tester.widget<EditableText>(find.byType(EditableText));
    expect(input.focusNode.hasPrimaryFocus, isTrue);
    await tester.pump(const Duration(seconds: 4));
    expect(input.focusNode.hasPrimaryFocus, isTrue);
    await tester.enterText(find.byType(TextField), '遥控器输入');
    expect(find.text('遥控器输入'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
