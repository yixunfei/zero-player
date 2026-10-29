import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/presentation/playback_surface.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  late Directory root;
  late AppServices services;
  late PlaybackController controller;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('player-layout-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.supervision.load();
    await services.settings.load();
    controller = PlaybackController(services, FakePlayerEngine());
  });
  tearDown(() async {
    await controller.close();
    await services.close();
    await root.delete(recursive: true);
  });
  for (final size in [const Size(320, 640), const Size(568, 320)]) {
    testWidgets(
      'long playback failure remains readable and actionable: $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        try {
          controller.error = List.filled(10, '播放线路检测失败，请检查网络连接或选择其他来源。').join();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PlaybackSurface(
                  controller: controller,
                  video: const ColoredBox(color: Colors.black),
                  transport: const Text('播放操作'),
                  title: '超长视频标题与线路信息需要在手机窄屏和横屏大字体下保持可用',
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
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('重试'));
          await tester.pumpAndSettle();
          expect(find.text('重试').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }
}
