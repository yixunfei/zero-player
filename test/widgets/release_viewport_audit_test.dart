import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zero_player/app/shell.dart';
import 'package:zero_player/features/music/domain/music_recommendation.dart';
import '../../test_support/mobile_app_fixture.dart';

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(568, 320),
    const Size(768, 1024),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('main pages remain usable at $size with enlarged text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = MobileAppFixture();
      await tester.runAsync(
        () => fixture.initialize(
          mode: size.width >= 1920 ? 'television' : 'auto',
        ),
      );
      fixture.services.musicRecommendations.items = const [
        MusicRecommendation('离线精选', '歌手', ''),
      ];
      await tester.runAsync(() async {
        await fixture.services.radio.load();
        await rootBundle.loadString('assets/live_candidates.json');
      });
      await fixture.pump(tester, size: size);
      final router = GoRouter.of(tester.element(find.byType(AppShell)));
      for (final route in [
        '/search',
        '/music',
        '/history',
        '/downloads',
        '/local',
        '/settings',
        '/live',
        '/radio',
        '/sources',
      ]) {
        router.go(route);
        for (var frame = 0; frame < 10; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'route=$route, size=$size',
        );
      }
      await fixture.finish(tester);
    });
  }
}
