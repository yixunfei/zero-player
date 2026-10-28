import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/radio/data/radio_repository.dart';
import 'package:zero_player/features/radio/presentation/radio_page.dart';
import 'package:zero_player/features/radio/presentation/radio_mini_player.dart';
import '../../test_support/fake_player_engine.dart';

late Directory root;
late FakePlayerEngine engine;
late AppServices services;

void main() {
  setUp(_initialize);
  tearDown(() async {
    await services.close();
    await root.delete(recursive: true);
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'radio persists after page disposal and mini controls work at $width',
      (tester) => _exercise(tester, width),
      timeout: const Timeout(Duration(seconds: 15)),
    );
  }
}

Future<void> _initialize() async {
  root = await Directory.systemTemp.createTemp('radio-background-');
  final db = AppDatabase.memory();
  services = AppServices.scoped(root, db, radioEngine: () => engine);
  await services.settings.load();
  await db.write('INSERT INTO app_meta VALUES(?,?)', [
    'radio_snapshot:$builtinRadioUrl',
    jsonEncode({
      'text':
          '#EXTM3U\n#EXTINF:-1 group-title="音乐",测试广播\nhttps://media.test/radio.mp3\n',
      'base': builtinRadioUrl,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }),
  ]);
  await services.radio.load();
}

Future<void> _exercise(WidgetTester tester, double width) async {
  engine = FakePlayerEngine();
  tester.view.physicalSize = Size(width, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RadioPage(services: services)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(ListTile, '测试广播'));
    await tester.pumpAndSettle();
    expect(engine.snapshot.playing, isTrue);
    await tester.tap(find.byTooltip('收藏电台'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消收藏电台'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RadioMiniPlayer(controller: services.radioPlayer)),
      ),
    );
    await tester.pumpAndSettle();
    expect(engine.snapshot.playing, isTrue);
    await tester.tap(find.byTooltip('暂停广播'));
    await tester.pumpAndSettle();
    expect(engine.snapshot.playing, isFalse);
    await tester.tap(find.byTooltip('播放广播'));
    await tester.pumpAndSettle();
    expect(engine.snapshot.playing, isTrue);
    await services.pauseRadioForVideo();
    await tester.pumpAndSettle();
    expect(engine.snapshot.playing, isFalse);
    await tester.tap(find.byTooltip('停止广播'));
    await tester.pumpAndSettle();
    expect(services.radioPlayer.active, isFalse);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(services.radioPlayer.close);
    await tester.runAsync(services.close);
  }
}
