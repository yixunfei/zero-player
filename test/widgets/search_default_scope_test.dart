import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zero_player/app/shell.dart';
import 'package:zero_player/features/search/presentation/search_status_panel.dart';
import '../../test_support/mobile_app_fixture.dart';

void main() {
  testWidgets(
    'entry source is preferred across all sources; discovery clears stale scope',
    (tester) async {
      final fixture = MobileAppFixture();
      late String current;
      await tester.runAsync(() async {
        await fixture.initialize();
        current = await fixture.services.sources.saveManual(
          '当前源',
          Uri.parse('https://current.test/api'),
        );
        await fixture.services.sources.saveManual(
          '其他源',
          Uri.parse('https://other.test/api'),
        );
      });
      await fixture.pump(tester);
      final router = GoRouter.of(tester.element(find.byType(AppShell)));
      router.go('/search?source=$current');
      await fixture.settle(tester);
      var controller = tester
          .widget<SearchStatusPanel>(find.byType(SearchStatusPanel))
          .controller;
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '仅当前来源'))
            .selected,
        isFalse,
      );
      await tester.tap(find.text('仅当前来源'));
      await fixture.settle(tester);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '仅当前来源'))
            .selected,
        isTrue,
      );
      router.go('/search?source=');
      await fixture.settle(tester);
      controller = tester
          .widget<SearchStatusPanel>(find.byType(SearchStatusPanel))
          .controller;
      expect(controller.preferredSourceId, isNull);
      fixture.services.searchSourceId = current;
      router.go('/');
      await fixture.settle(tester);
      expect(fixture.services.searchSourceId, isNull);
      router.go('/search');
      await fixture.settle(tester);
      controller = tester
          .widget<SearchStatusPanel>(find.byType(SearchStatusPanel))
          .controller;
      expect(controller.preferredSourceId, isNull);
      router.push('/detail/$current/1');
      await fixture.settle(tester);
      expect(fixture.services.searchSourceId, current);
      router.pop();
      await fixture.settle(tester);
      expect(fixture.services.searchSourceId, isNull);
      await fixture.finish(tester);
    },
  );
}
