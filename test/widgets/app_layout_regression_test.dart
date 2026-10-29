import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/application_fullscreen.dart';
import '../../test_support/mobile_app_fixture.dart';

void main() {
  for (final size in [const Size(768, 1024), const Size(1365, 768)]) {
    testWidgets(
      'wide layout retains fullscreen and adapts when resized: $size',
      (tester) async {
        final fixture = MobileAppFixture();
        await tester.runAsync(fixture.initialize);
        await fixture.pump(tester, size: size);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(AppFullscreenButton), findsOneWidget);
        expect(fixture.services.platform.appFullscreen.value, isTrue);
        expect(tester.takeException(), isNull);

        tester.view.physicalSize = const Size(390, 844);
        await fixture.settle(tester);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(AppFullscreenButton), findsNothing);
        expect(fixture.services.platform.appFullscreen.value, isFalse);
        expect(tester.takeException(), isNull);
        await fixture.finish(tester);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.windows,
      }),
    );
  }
}
