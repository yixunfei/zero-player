import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/presentation/skip_marks_dialog.dart';
import '../../test_support/fake_player_engine.dart';

late Directory root;
late AppServices services;
late PlaybackController player;

void main() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('skip-session-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.settings.load();
    await services.supervision.load();
    await services.gateway.start();
    await services.settings.update({'contentFilter': false});
    player = PlaybackController(services, FakePlayerEngine());
    await player.open(
      PlaybackRequest(
        CatalogItem(
          sourceId: 'fixture',
          id: 'movie',
          title: 'movie',
          lines: [
            PlayLine('main', [
              Episode('1', Uri.parse('https://example.org/1.mp4')),
              Episode('2', Uri.parse('https://example.org/2.mp4')),
            ]),
          ],
        ),
      ),
    );
  });
  tearDown(() async {
    await player.close();
    await services.close();
    await root.delete(recursive: true);
  });
  testWidgets('an open manual mark editor cannot write into a new episode', (
    tester,
  ) async {
    await _open(tester);
    final oldKey = player.workKey;
    await tester.tap(find.text('按秒数添加片头 / 中段 / 片尾'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '终点（秒）'), '4');
    await tester.runAsync(() => player.select(0, 1));
    await tester.runAsync(() async {
      await tester.tap(find.text('保存'));
      await Future<void>.delayed(const Duration(milliseconds: 380));
    });
    await tester.pumpAndSettle();
    expect(await services.skips.list(player.workKey), isEmpty);
    expect(await services.skips.list(oldKey), isEmpty);
    expect(find.textContaining('视频已切换'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'a stale manager cannot change work preferences after playback switches',
    (tester) async {
      await _open(tester);
      await tester.runAsync(() => player.select(0, 1));
      await tester.runAsync(() async {
        await tester.tap(find.text('此作品启用自动跳过'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(await services.skips.workEnabled(player.seriesKey), isTrue);
      expect(find.textContaining('视频已切换'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSkipMarks(context, services, player),
            child: const Text('管理片段'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('管理片段'));
  await tester.pumpAndSettle();
}
