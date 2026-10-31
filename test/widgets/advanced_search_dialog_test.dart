import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/search/application/search_options.dart';
import 'package:zero_player/features/search/presentation/advanced_search_dialog.dart';

void main() {
  testWidgets('advanced search fits narrow screen and submits fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SearchOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAdvancedSearch(
                  context,
                  const SearchOptions(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '2026');
    await tester.tap(find.text('应用并搜索'));
    await tester.pumpAndSettle();
    expect(result?.year, '2026');
    expect(tester.takeException(), isNull);
  });
}
