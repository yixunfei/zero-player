import 'dart:io';
import 'package:zero_player/features/music/application/music_downloads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/domain/music_track.dart';
import 'package:zero_player/features/music/presentation/music_page.dart';
import 'package:zero_player/features/music/presentation/music_player.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  testWidgets(
    'downloaded search result stays visible when online search fails',
    (tester) async {
      final (root, services, _) = (await tester.runAsync(_setup))!;
      final track = services.musicBrowser.result.tracks.single;
      services.musicDownloads.items = [
        MusicDownload(track, 'complete', 100, entry: 'audio.mp3'),
      ];
      services.musicBrowser.result = const MusicSearchResult([]);
      services.musicBrowser.error = '网络不可用';
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MusicPage(services: services)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('music-test')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining('已下载 · 本地播放'), findsOneWidget);
        expect(find.byTooltip('已下载 · 优先本地播放'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _closeFixture(tester, services, root);
      }
    },
  );
  for (final size in [
    const Size(390, 850),
    const Size(844, 390),
    const Size(1280, 850),
  ]) {
    testWidgets(
      'music page and mini player at $size with enlarged text',
      (tester) => _exercise(tester, size),
    );
  }
}

Future<void> _exercise(WidgetTester tester, Size size) async {
  final setup = (await tester.runAsync(_setup))!;
  final (root, services, engine) = setup;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Widget frame(Widget child) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: const TextScaler.linear(1.6),
      ),
      child: Scaffold(body: child),
    ),
  );
  try {
    await tester.pumpWidget(frame(MusicPage(services: services)));
    await tester.pumpAndSettle();
    expect(find.text('MY FREE MP3'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('music-test')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    if (tester.getCenter(find.byKey(const ValueKey('music-test'))).dy >
        size.height - 100) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -150));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('music-test')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    for (var i = 0; i < 50 && services.musicPlayer.loading; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle();
    expect(engine.snapshot.playing, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      frame(MusicPlayer(controller: services.musicPlayer, compact: true)),
    );
    await tester.pumpAndSettle();
    expect(engine.snapshot.playing, isTrue);
    await tester.tap(find.byTooltip('暂停音乐'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(engine.snapshot.playing, isFalse);
    await tester.tap(find.byTooltip('播放音乐'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(engine.snapshot.playing, isTrue);
    await tester.tap(find.byTooltip('停止音乐'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(services.musicPlayer.active, isFalse);
    expect(services.musicBrowser.query, '测试');
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await _closeFixture(tester, services, root);
  }
}

Future<(Directory, AppServices, FakePlayerEngine)> _setup() async {
  final root = await Directory.systemTemp.createTemp('music-page-');
  final engine = FakePlayerEngine();
  final services = AppServices.scoped(
    root,
    AppDatabase.memory(),
    musicEngine: () => engine,
  );
  await services.settings.load();
  await services.musicLibrary.load();
  await services.musicDownloads.load();
  services.musicBrowser.query = '测试';
  services.musicBrowser.result = MusicSearchResult([
    MusicTrack(
      id: 'test',
      title: '测试音乐',
      artist: '测试歌手',
      url: Uri.parse('https://example.com/test.mp3'),
      fetchedAt: DateTime.now(),
    ),
  ]);
  services.musicPlayer;
  return (root, services, engine);
}

Future<void> _closeFixture(
  WidgetTester tester,
  AppServices services,
  Directory root,
) async {
  var flushed = false;
  services.musicLibrary.pendingWrites.then((_) => flushed = true);
  for (var i = 0; i < 50 && !flushed; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(flushed, isTrue);
  var closed = false;
  Object? closeError;
  services.close().then(
    (_) {
      closed = true;
    },
    onError: (Object error) {
      closeError = error;
      closed = true;
    },
  );
  for (var i = 0; i < 300 && !closed; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(closed, isTrue);
  expect(closeError, isNull);
  await tester.runAsync(() => root.delete(recursive: true));
}
