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
  setUp(_createPlayingSession);
  tearDown(() async {
    await controller.close();
    await services.close();
    await root.delete(recursive: true);
  });
  testWidgets(
    'direction keys act immediately; click toggles; bottom wakes controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaybackSurface(
              controller: controller,
              video: const ColoredBox(color: Colors.black),
              transport: const Text('controls'),
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
      expect(engine.seeks.last, const Duration(seconds: 22));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(engine.snapshot.volume, 65);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('controls').hitTestable(), findsNothing);
      await tester.tapAt(const Offset(400, 570));
      await tester.pump();
      expect(engine.snapshot.playing, isTrue);
      expect(find.text('controls').hitTestable(), findsOneWidget);
      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      expect(engine.snapshot.playing, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final size in [const Size(320, 640), const Size(568, 320)]) {
    testWidgets('time, buffer and quick actions remain readable at $size', (
      tester,
    ) async {
      _viewport(tester, size);
      var marks = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PlayerTransport(
                controller: controller,
                fullscreen: false,
                fit: BoxFit.contain,
                onFullscreen: () {},
                onOptions: () {},
                onMark: () => marks++,
                onScreenshot: () {},
                onFit: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('playback-time')), findsOneWidget);
      expect(find.text('00:12 / 02:00'), findsOneWidget);
      final slider = tester.widget<Slider>(
        find.descendant(
          of: find.byType(TimelineSlider),
          matching: find.byType(Slider),
        ),
      );
      expect(slider.secondaryTrackValue, 40000);
      await tester.tap(find.byTooltip('标记不良信息 · 最近 4 秒'));
      expect(marks, 1);
      expect(engine.snapshot.playing, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _createPlayingSession() async {
  root = await Directory.systemTemp.createTemp('player-controls-');
  services = AppServices.scoped(root, AppDatabase.memory());
  await services.settings.load();
  engine = FakePlayerEngine();
  controller = PlaybackController(services, engine);
  engine.snapshot = const PlaybackSnapshot(
    position: Duration(seconds: 12),
    duration: Duration(minutes: 2),
    buffer: Duration(seconds: 40),
    playing: true,
    volume: 60,
  );
  controller.state = engine.snapshot;
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.6;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}
