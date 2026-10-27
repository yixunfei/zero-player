import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/scroll_reveal_header.dart';

void main() {
  testWidgets(
    'resize during ballistic scrolling keeps floating filters usable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: controller,
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ScrollRevealHeader(
                  child: Material(
                    child: LayoutBuilder(
                      builder: (context, bounds) => SizedBox(
                        height: bounds.maxWidth < 500 ? 180 : 80,
                        child: TextButton(
                          onPressed: () => presses++,
                          child: const Text('筛选频道'),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: 80,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 80, child: Text('节目 $i')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -700),
        2400,
      );
      await tester.pump(const Duration(milliseconds: 80));
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('筛选频道').hitTestable(), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 220));
      await tester.pumpAndSettle();
      expect(find.text('筛选频道').hitTestable(), findsOneWidget);
      await tester.tap(find.text('筛选频道'));
      expect(presses, 1);
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('筛选频道').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
