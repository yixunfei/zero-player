import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/discovery/presentation/discovery_toolbar.dart';

void main() {
  for (final width in [320.0, 390.0, 760.0, 1280.0]) {
    testWidgets('search shares the channel row at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var searched = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: DiscoveryToolbar(
                sources: const [],
                channel: '',
                providerName: '精选推荐',
                aggregate: false,
                isDefault: false,
                onChannel: (_) {},
                onLayout: (_) {},
                onSaveDefault: () {},
                onRefresh: () {},
                onSearch: () => searched = true,
              ),
            ),
          ),
        ),
      );
      final search = find.byKey(const ValueKey('home-search'));
      final channel = find.byType(DropdownButtonFormField<String>);
      expect(
        tester.getRect(search).center.dy,
        closeTo(tester.getRect(channel).center.dy, 1),
      );
      expect(tester.getSize(search).width, greaterThan(50));
      await tester.tap(search);
      expect(searched, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
