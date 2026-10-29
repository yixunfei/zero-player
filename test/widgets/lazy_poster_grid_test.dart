import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/widgets.dart';

void main() {
  testWidgets(
    'tablet grid constructs only visible cards from thousands of results',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var built = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosterGrid.builder(
              itemCount: 5000,
              itemBuilder: (_, index) {
                built++;
                return Text('节目 $index');
              },
            ),
          ),
        ),
      );
      expect(built, lessThan(50));
      expect(find.text('节目 0'), findsOneWidget);
      expect(find.text('节目 4999'), findsNothing);
      await tester.drag(find.byType(GridView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(built, lessThan(100));
      expect(tester.takeException(), isNull);
    },
  );
}
