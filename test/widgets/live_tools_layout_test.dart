import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/live/presentation/live_probe_dialog.dart';
import 'package:zero_player/features/live/presentation/live_schedule_dialog.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
      'live guide and batch tools fit $size and offer concurrency selection',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('live-tools-'),
        ))!;
        final services = AppServices.scoped(root, AppDatabase.memory());
        addTearDown(() async {
          await tester.runAsync(() async {
            await services.close();
            await root.delete(recursive: true);
          });
        });
        const channel = LiveChannel(
          id: 'one',
          listId: 'none',
          name: 'CCTV1',
          urls: [],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LiveScheduleDialog(
                repository: services.live,
                channel: channel,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('暂无匹配节目'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LiveProbeDialog(
                services: services,
                channels: const [channel],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('开始检测'), findsOneWidget);
        final dropdown = find.byType(DropdownButton<int>);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('16 路并发').last);
        await tester.pumpAndSettle();
        expect(tester.widget<DropdownButton<int>>(dropdown).value, 16);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
