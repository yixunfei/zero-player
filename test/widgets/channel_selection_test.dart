import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/discovery/presentation/discovery_toolbar.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('long channel menu reopens at current item at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = width < 400
          ? 1.6
          : 1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var current = '60';
      final sources = List.generate(
        80,
        (i) => VideoSource(
          id: '$i',
          name: i == 60 ? '超长频道名称 - 第六十个资源服务商 及其提供的视频内容目录' : '频道 $i',
          favorite: i == 60,
          endpoint: Uri.https('source$i.test'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.fromLTRB(24, 170, 24, 24),
              child: StatefulBuilder(
                builder: (context, setState) => DiscoveryToolbar(
                  sources: sources,
                  channel: current,
                  providerName: '精选推荐',
                  aggregate: false,
                  isDefault: false,
                  onChannel: (value) => setState(() => current = value),
                  onLayout: (_) {},
                  onSaveDefault: () {},
                  onRefresh: () {},
                  onSearch: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      _expectSelected(tester, '60');
      final next = find.descendant(
        of: find.byType(ListView),
        matching: find.text('频道 61'),
      );
      await tester.scrollUntilVisible(
        next,
        48,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(current, '61');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      _expectSelected(tester, '61');
      expect(tester.takeException(), isNull);
    });
  }
}

void _expectSelected(WidgetTester tester, String id) {
  final list = find.byType(ListView);
  expect(list, findsOneWidget);
  final scroll = tester.state<ScrollableState>(
    find.descendant(of: list, matching: find.byType(Scrollable)).first,
  );
  expect(scroll.position.pixels, greaterThan(0));
  expect(
    find
        .descendant(
          of: list,
          matching: find.text(
            id == '60' ? '超长频道名称 - 第六十个资源服务商 及其提供的视频内容目录' : '频道 $id',
          ),
        )
        .hitTestable(),
    findsOneWidget,
  );
  expect(
    find.descendant(of: list, matching: find.text('频道 0')).hitTestable(),
    findsNothing,
  );
}
