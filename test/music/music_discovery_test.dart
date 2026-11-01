import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/data/music_recommendations.dart';
import 'package:zero_player/features/music/presentation/music_discovery.dart';
import 'package:zero_player/features/music/presentation/music_source_selector.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  for (final size in [
    const Size(390, 850),
    const Size(844, 390),
    const Size(1280, 850),
  ]) {
    testWidgets(
      'music cover grid at $size with enlarged text searches its metadata',
      (tester) async {
        final (root, services) = (await tester.runAsync(() async {
          final root = await Directory.systemTemp.createTemp('music-grid-');
          return (
            root,
            AppServices.scoped(
              root,
              AppDatabase.memory(),
              musicEngine: () => FakePlayerEngine(),
            ),
          );
        }))!;
        services.musicRecommendations.items = [
          for (var i = 0; i < 12; i++) MusicRecommendation('音乐 $i', '歌手', ''),
        ];
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? query;
        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [servicesProvider.overrideWithValue(services)],
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.6)),
                  child: child!,
                ),
                home: Scaffold(
                  body: MusicDiscovery(
                    services: services,
                    onSearch: (value) => query = value,
                    controls: MusicSourceSelector(
                      services: services,
                      value: 'myfreemp3',
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          );
          final first = find.byKey(const ValueKey('music-recommendation-0'));
          await tester.scrollUntilVisible(first, 150);
          await tester.pumpAndSettle();
          await tester.tap(first);
          await tester.pumpAndSettle();
          expect(query, '音乐 0 歌手');
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(find.text('场景'), -200);
          await tester.ensureVisible(find.text('场景'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('场景'));
          await tester.pumpAndSettle();
          expect(services.musicRecommendations.category, '场景');
          expect(find.text('专注钢琴'), findsOneWidget);
          await tester.ensureVisible(find.text('夜间放松'));
          await tester.tap(find.text('夜间放松'));
          await tester.pumpAndSettle();
          expect(services.musicRecommendations.chart, 'night');
          expect(
            services.musicRecommendations.items.first.title,
            'Come Away with Me',
          );
          expect(tester.takeException(), isNull);
          await _checkDialog(tester);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _close(tester, services);
          await tester.runAsync(() => root.delete(recursive: true));
        }
      },
    );
  }
}

Future<void> _checkDialog(WidgetTester tester) async {
  await tester.runAsync(
    () => rootBundle.loadString('assets/catalogs/music/lx-native-catalog.json'),
  );
  final sources = find.byTooltip('音乐渠道与 LX 音源');
  await tester.scrollUntilVisible(sources, -200);
  await tester.ensureVisible(sources);
  await tester.pumpAndSettle();
  await tester.tap(sources);
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(AlertDialog), findsOneWidget);
  final target = find.text('huibq · v1.2.0');
  final scroll = find
      .descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var i = 0; i < 40 && target.evaluate().isEmpty; i++) {
    await tester.drag(scroll, const Offset(0, -250));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _close(WidgetTester tester, AppServices services) async {
  var done = false;
  Object? error;
  services.close().then(
    (_) => done = true,
    onError: (Object failure) {
      error = failure;
      done = true;
    },
  );
  for (var i = 0; i < 300 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done, isTrue);
  expect(error, isNull);
}
