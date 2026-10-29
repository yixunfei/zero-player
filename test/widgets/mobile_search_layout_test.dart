import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zero_player/app/shell.dart';
import 'package:zero_player/app/poster_card.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/catalog/presentation/source_choices_dialog.dart';
import 'package:zero_player/features/search/presentation/search_status_panel.dart';
import '../../test_support/mobile_app_fixture.dart';

void main() {
  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(844, 390), 1.0),
    (const Size(320, 640), 1.6),
    (const Size(844, 390), 1.6),
  ]) {
    testWidgets('search, keyboard and source dialog fit $size at $scale', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = MobileAppFixture();
      await tester.runAsync(fixture.initialize);
      await fixture.pump(tester, size: size);
      final router = GoRouter.of(tester.element(find.byType(AppShell)));
      router.go('/search');
      await fixture.settle(tester);
      final controller = tester
          .widget<SearchStatusPanel>(find.byType(SearchStatusPanel))
          .controller;
      controller.query = '海军罪案调查处';
      for (var i = 0; i < 30; i++) {
        controller.items.add(
          CatalogItem(
            sourceId: 'source-$i',
            id: '$i',
            title: '海军罪案调查处：溯源第三季 - 第 $i 个搜索结果',
            year: '2026',
            remarks: '更新至04集 · 超长版本说明',
          ),
        );
        controller.statuses['source-$i'] = '接口检测失败，可重试或切换来源';
        controller.sourceNames['source-$i'] = '超长资源频道名称 第 $i 个频道资源地址';
        controller.failedSources.add('source-$i');
      }
      controller.notifyListeners();
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(
        bottom: size.height > 500 ? 260 : 140,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsNothing);
      tester.view.resetViewInsets();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      final poster = find.byWidgetPredicate(
        (widget) => widget is PosterCard && widget.title.contains('第 0 个'),
      );
      await tester.scrollUntilVisible(
        poster,
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('search-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(poster);
      await fixture.settle(tester);
      expect(find.byType(SourceChoicesDialog), findsOneWidget);
      expect(find.text('取消').hitTestable(), findsOneWidget);
      final dialog = tester.getRect(find.byType(Dialog));
      expect(dialog.left, greaterThanOrEqualTo(0));
      expect(dialog.right, lessThanOrEqualTo(size.width));
      expect(dialog.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await fixture.settle(tester);
      expect(find.byType(SourceChoicesDialog), findsNothing);
      expect(router.state.uri.path, '/search');
      await fixture.finish(tester);
    });
  }
}
