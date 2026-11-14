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
import 'package:zero_player/features/music/data/music_catalog_api.dart';
import 'package:zero_player/features/music/data/music_recommendations.dart';
import 'package:zero_player/features/music/presentation/music_catalog_controls.dart';
import 'package:zero_player/features/music/presentation/music_page.dart';
import '../test_support/fixture_project.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'music homepage discovery searches chosen channel and MY FREE MP3 decodes',
    _exercise,
    skip: !const bool.fromEnvironment('RUN_MUSIC_ONLINE'),
  );
  testWidgets(
    'online music browses provider charts and appends playlist and track pages',
    _browseCatalog,
    skip: !const bool.fromEnvironment('RUN_MUSIC_ONLINE'),
  );
}

Future<void> _browseCatalog(WidgetTester tester) async {
  final root = await Directory.systemTemp.createTemp('music-catalog-native-');
  final services = AppServices.scoped(root, AppDatabase.memory());
  try {
    await services.settings.load();
    await services.supervision.load();
    await services.musicRecommendations.initialize();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          home: Scaffold(body: MusicPage(services: services)),
        ),
      ),
    );
    await _browseRank(tester, services.musicRecommendations);
    await _browsePlaylistPages(tester);
    await _browsePlaylistTracks(tester);
    debugPrint(
      'MUSIC_CATALOG_NATIVE_OK chartSongs=${services.musicRecommendations.items.length} playlistTracks=100',
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await services.close();
    await root.delete(recursive: true);
  }
}

Future<void> _browseRank(WidgetTester tester, MusicRecommendations feed) async {
  await _tap(tester, find.text('榜单'));
  await _until(tester, () => feed.charts.length > 50 && !feed.loading);
  expect(feed.items, isNotEmpty);
  final first = feed.items.length;
  await tester.scrollUntilVisible(
    find.text('加载更多曲目'),
    720,
    scrollable: find
        .descendant(
          of: find.byKey(const PageStorageKey('music-discovery')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await _tap(tester, find.text('加载更多曲目'));
  await _until(tester, () => !feed.loading && feed.items.length > first);
  expect(feed.items.last.rank, greaterThan(50));
}

Future<void> _browsePlaylistPages(WidgetTester tester) async {
  await _tap(tester, find.text('在线歌单'));
  final viewport = find.byKey(const PageStorageKey('music-style-lists'));
  await _tap(tester, find.text('QQ 音乐歌单'));
  await _until(tester, () => find.text('热门').evaluate().isNotEmpty);
  await _tap(tester, find.text('热门'));
  final picker = find.byType(DropdownButton<MusicCatalogOption>);
  await _until(tester, () => picker.evaluate().isNotEmpty);
  expect(
    tester
        .widget<DropdownButton<MusicCatalogOption>>(picker)
        .items
        ?.any((item) => item.value?.name == 'AI歌单'),
    isTrue,
  );
  final total = find.textContaining(RegExp(r'源站 \d+ 个歌单'));
  await _until(tester, () => total.evaluate().isNotEmpty);
  final listScroll = find.descendant(
    of: viewport,
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.text('加载更多歌单'),
    480,
    scrollable: listScroll,
  );
  final previous = tester
      .widget<ListView>(viewport)
      .childrenDelegate
      .estimatedChildCount!;
  await _tap(tester, find.text('加载更多歌单'));
  await _until(
    tester,
    () =>
        tester
            .widget<ListView>(viewport)
            .childrenDelegate
            .estimatedChildCount! >
        previous,
  );

  await tester.scrollUntilVisible(
    find.text('QQ 音乐歌单'),
    -500,
    scrollable: listScroll,
  );
  await tester.pump();
}

Future<void> _browsePlaylistTracks(WidgetTester tester) async {
  final list = find.ancestor(
    of: find.byTooltip('复制歌单网页链接').first,
    matching: find.byType(ListTile),
  );
  await _tap(tester, list);
  await _until(
    tester,
    () => find.textContaining('已加载 50 首').evaluate().isNotEmpty,
  );
  expect(
    tester
        .widget<MusicCatalogCopyButton>(
          find.byType(MusicCatalogCopyButton).first,
        )
        .uri
        .host,
    'y.qq.com',
  );
  final details = find.byType(ListView).first;
  final detailScroll = find
      .descendant(of: details, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(
    find.text('加载更多曲目'),
    700,
    scrollable: detailScroll,
  );
  await _tap(tester, find.text('加载更多曲目'));
  await tester.scrollUntilVisible(
    find.byTooltip('返回在线歌单'),
    -850,
    scrollable: detailScroll,
  );
  await _until(
    tester,
    () => find.textContaining('已加载 100 首').evaluate().isNotEmpty,
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final watch = Stopwatch()..start();
  while (!done() && watch.elapsed < const Duration(seconds: 20)) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  expect(done(), isTrue);
}

Future<void> _exercise(WidgetTester tester) async {
  final root = await Directory.systemTemp.createTemp('music-cover-native-');
  final services = AppServices.scoped(root, AppDatabase.memory());
  final key = GlobalKey();
  try {
    await services.settings.load();
    await services.supervision.load();
    await services.musicRecommendations.initialize();
    expect(services.musicRecommendations.showingFallback, isFalse);
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
    services.musicBrowser.selectProvider('myfreemp3');
    await tester.tap(find.byType(PosterCard).first);
    await tester.pump();
    expect(services.musicBrowser.provider, 'myfreemp3');
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
      'MUSIC_DISCOVERY_NATIVE_OK recommendations=${services.musicRecommendations.items.length} searchResults=${services.musicBrowser.result.tracks.length}',
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await services.close();
    await root.delete(recursive: true);
  }
}
