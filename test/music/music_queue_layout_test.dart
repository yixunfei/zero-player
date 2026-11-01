import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/application/music_controller.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/music/domain/music_track.dart';
import 'package:zero_player/features/music/presentation/music_player.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  for (final size in [
    const Size(320, 700),
    const Size(390, 850),
    const Size(844, 390),
    const Size(1280, 850),
  ]) {
    testWidgets(
      'queue controls and one seek on drag release at $size',
      (tester) => _exercise(tester, size),
    );
  }
}

Future<void> _exercise(WidgetTester tester, Size size) async {
  final (http, player, engine) = (await tester.runAsync(() async {
    final http = MediaHttpClient();
    final engine = FakePlayerEngine();
    final player = MusicController(
      MusicRepository(MyFreeMp3Client(DocumentClient(http))),
      () => engine,
    );
    await player.select([
      for (final id in ['a', 'b', 'c'])
        MusicTrack(
          id: id,
          title: '测试歌曲 $id',
          artist: '测试歌手',
          url: Uri.parse('https://example.com/$id.mp3'),
          fetchedAt: DateTime.now(),
        ),
    ], 0);
    return (http, player, engine);
  }))!;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  try {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MusicPlayer(controller: player),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (size.width < 480) {
      expect(
        tester.getSize(find.text('测试歌曲 a')).width,
        greaterThan(size.width * .7),
      );
    }
    await _dragProgress(tester, engine);
    final position = player.snapshot.position;
    await tester.tap(find.byTooltip('播放队列（3 首）'));
    await tester.pumpAndSettle();
    final last = find.byKey(const ValueKey('music-queue-myfreemp3:c'));
    await tester.scrollUntilVisible(
      last,
      120,
      scrollable: find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(
      find.descendant(of: last, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出队列'));
    await tester.pumpAndSettle();
    expect(player.queue.map((t) => t.id), ['a', 'b']);
    await tester.tap(find.text('清空其他歌曲'));
    await tester.pumpAndSettle();
    expect(player.queue.single.id, 'a');
    expect(player.snapshot.position, position);
    expect(engine.opens, 1);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(player.close);
    http.close();
  }
}

Future<void> _dragProgress(WidgetTester tester, FakePlayerEngine engine) async {
  final slider = find.byType(Slider);
  final rect = tester.getRect(slider);
  final gesture = await tester.startGesture(
    Offset(rect.left + rect.width * .25, rect.center.dy),
  );
  for (final fraction in [.4, .5, .65]) {
    await gesture.moveTo(
      Offset(rect.left + rect.width * fraction, rect.center.dy),
    );
    await tester.pump();
  }
  expect(engine.seeks, isEmpty);
  await gesture.up();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pumpAndSettle();
  expect(engine.seeks, hasLength(1));
  expect(engine.seeks.single, greaterThan(Duration.zero));
}
