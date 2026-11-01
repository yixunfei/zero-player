import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/app_theme.dart';
import 'package:zero_player/app/poster_card.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/presentation/music_page.dart';
import '../test_support/fixture_project.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'music cover discovery searches chosen channel and QQMP3 decodes',
    _exercise,
    skip: !const bool.fromEnvironment('RUN_MUSIC_ONLINE'),
  );
}

Future<void> _exercise(WidgetTester tester) async {
  final root = await Directory.systemTemp.createTemp('music-cover-native-');
  final services = AppServices.scoped(root, AppDatabase.memory());
  final key = GlobalKey();
  try {
    await services.settings.load();
    await services.supervision.load();
    await services.musicRecommendations.load('hot', refresh: true);
    expect(services.musicRecommendations.items, isNotEmpty);
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1280, 850));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark, false, 'dark'),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: MusicPage(services: services),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PosterCard), findsWidgets);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final screenshot = await boundary.toImage(pixelRatio: 1);
    final png = await screenshot.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '${fixtureProjectRoot()}/build/music-discovery-home.png',
    ).writeAsBytes(png!.buffer.asUint8List());
    screenshot.dispose();
    services.musicBrowser.selectProvider('qqmp3');
    await tester.tap(find.byType(PosterCard).first);
    await tester.pump();
    expect(services.musicBrowser.provider, 'qqmp3');
    expect(
      services.musicBrowser.query,
      services.musicRecommendations.items.first.query,
    );
    await services.musicBrowser.search('Adele');
    expect(services.musicBrowser.result.tracks, isNotEmpty);
    await services.musicPlayer.select(services.musicBrowser.result.tracks, 0);
    final watch = Stopwatch()..start();
    while (services.musicPlayer.snapshot.position <
            const Duration(seconds: 1) &&
        watch.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(services.musicPlayer.error, isNull);
    expect(services.musicPlayer.playing, isTrue);
    expect(services.musicPlayer.snapshot.position, greaterThan(Duration.zero));
    debugPrint(
      'MUSIC_DISCOVERY_NATIVE_OK recommendations=${services.musicRecommendations.items.length} qqResults=${services.musicBrowser.result.tracks.length}',
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await services.close();
    await root.delete(recursive: true);
  }
}
