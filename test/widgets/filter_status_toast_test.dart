import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import 'package:zero_player/features/playback/presentation/filter_playback_overlay.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  testWidgets(
    'status displays only during playback and never reappears on rebuild',
    (tester) async {
      late Directory root;
      late AppServices services;
      late PlaybackController player;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('filter-toast-');
        services = AppServices.scoped(root, AppDatabase.memory());
        player = PlaybackController(services, FakePlayerEngine());
      });
      Future<void> show({required bool playing}) async {
        player.state = PlaybackSnapshot(playing: playing);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [FilterPlaybackOverlay(controller: player)],
              ),
            ),
          ),
        );
      }

      try {
        player.filterStatus = '后台检测已启用 · 播放流畅优先';
        await show(playing: false);
        expect(find.byKey(const ValueKey('filter-status-toast')), findsNothing);
        await show(playing: true);
        expect(
          find.byKey(const ValueKey('filter-status-toast')),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 2999));
        expect(
          find.byKey(const ValueKey('filter-status-toast')),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 2));
        expect(find.byKey(const ValueKey('filter-status-toast')), findsNothing);
        await show(playing: true);
        await show(playing: false);
        await show(playing: true);
        expect(find.byKey(const ValueKey('filter-status-toast')), findsNothing);
        player.filterStatus = '后台检测已恢复 · 播放流畅优先';
        await show(playing: true);
        expect(
          find.byKey(const ValueKey('filter-status-toast')),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 3));
        expect(find.byKey(const ValueKey('filter-status-toast')), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await player.close();
          await services.close();
          await root.delete(recursive: true);
        });
      }
    },
  );
}
