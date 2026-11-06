import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import 'package:zero_player/features/playback/presentation/playback_surface.dart';
import '../../test_support/fake_player_engine.dart';

late Directory root;
late AppServices services;
late FakePlayerEngine engine;
late PlaybackController player;
const _center = Offset(400, 300);

void main() {
  setUp(_initialize);
  tearDown(() async {
    await player.close();
    await services.close();
    await root.delete(recursive: true);
  });
  testWidgets('first hidden tap reveals controls; second pauses with a badge', (
    tester,
  ) async {
    await _show(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('播放操作').hitTestable(), findsNothing);
    await tester.tapAt(_center);
    await tester.pump();
    expect(engine.snapshot.playing, isTrue);
    expect(find.text('播放操作').hitTestable(), findsOneWidget);
    await tester.tapAt(_center);
    await tester.pump();
    expect(engine.snapshot.playing, isFalse);
    expect(find.text('已暂停'), findsOneWidget);
    await tester.pump(const Duration(minutes: 30));
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('播放操作').hitTestable(), findsOneWidget);
    await tester.tapAt(_center);
    await tester.pump();
    expect(engine.snapshot.playing, isTrue);
    expect(find.text('已暂停'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('unlock stays reachable after long playback and buffering', (
    tester,
  ) async {
    await _show(tester, locked: true);
    await tester.pump(const Duration(hours: 2));
    expect(find.byTooltip('解除防误触').hitTestable(), findsOneWidget);
    engine.emit(const PlaybackSnapshot(playing: true, buffering: true));
    await tester.pump();
    await tester.tapAt(_center);
    await tester.pump();
    expect(engine.snapshot.playing, isTrue);
    await tester.dragFrom(_center, const Offset(100, 50));
    await tester.pump();
    expect(engine.seeks, isEmpty);
    expect(engine.snapshot.rate, 1);
    await tester.tap(find.byTooltip('解除防误触'));
    await tester.pump();
    expect(find.text('播放操作').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('locked error actions cannot swallow unlock or change playback', (
    tester,
  ) async {
    var actions = 0;
    player.error = '网络中断';
    await _show(
      tester,
      locked: true,
      errorAction: TextButton(
        onPressed: () => actions++,
        child: const Text('切换来源'),
      ),
    );
    await tester.tap(find.text('切换来源'), warnIfMissed: false);
    await tester.pump();
    expect(actions, 0);
    expect(engine.snapshot.playing, isTrue);
    await tester.tap(find.byTooltip('解除防误触'));
    await tester.pump();
    await tester.tap(find.text('切换来源'));
    await tester.pump();
    expect(actions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('buffering and completed states do not display a pause badge', (
    tester,
  ) async {
    await _show(tester);
    engine.emit(const PlaybackSnapshot(buffering: true));
    await tester.pump();
    expect(find.text('已暂停'), findsNothing);
    engine.emit(const PlaybackSnapshot(completed: true));
    await tester.pump();
    expect(find.text('已暂停'), findsNothing);
    player.error = '播放失败';
    engine.emit(const PlaybackSnapshot());
    await tester.pump();
    expect(find.text('已暂停'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _initialize() async {
  root = await Directory.systemTemp.createTemp('playback-touch-');
  services = AppServices.scoped(root, AppDatabase.memory());
  await services.settings.load();
  await services.supervision.load();
  engine = FakePlayerEngine();
  player = PlaybackController(services, engine);
  player.request = PlaybackRequest(
    CatalogItem(
      sourceId: 'fixture',
      id: 'movie',
      title: 'movie',
      lines: [
        PlayLine('main', [
          Episode('1', Uri.parse('https://example.invalid/movie.mp4')),
        ]),
      ],
    ),
  );
  engine.snapshot = const PlaybackSnapshot(
    playing: true,
    position: Duration(seconds: 12),
    duration: Duration(minutes: 2),
  );
  player.state = engine.snapshot;
}

Future<void> _show(
  WidgetTester tester, {
  bool locked = false,
  Widget? errorAction,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => PlaybackSurface(
          controller: player,
          video: const ColoredBox(color: Colors.black),
          transport: const Text('播放操作'),
          title: 'movie',
          onBack: () {},
          onOptions: () {},
          locked: locked,
          onLock: (value) => setState(() => locked = value),
          gestures: true,
          errorAction: errorAction,
        ),
      ),
    ),
  ),
);
