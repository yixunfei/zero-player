import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zero_player/core/platform/platform_services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'small window restores native bounds and application fullscreen',
    (tester) async {
      await windowManager.ensureInitialized();
      final wasTop = await windowManager.isAlwaysOnTop();
      final wasMaximized = await windowManager.isMaximized();
      if (wasMaximized) await windowManager.unmaximize();
      final bounds = await windowManager.getBounds();
      final platform = PlatformServices();
      try {
        await platform.setAppFullscreen(true);
        await platform.fullscreen(true);
        await platform.pictureInPicture();
        expect(await windowManager.isAlwaysOnTop(), isTrue);
        expect(platform.smallWindow, isTrue);
        await platform.restorePlayerWindow();
        expect(platform.smallWindow, isFalse);
        expect(await windowManager.isAlwaysOnTop(), wasTop);
        expect(await windowManager.isFullScreen(), isTrue);
        await platform.setAppFullscreen(false);
        final restored = await windowManager.getBounds();
        expect(restored.left, closeTo(bounds.left, 2));
        expect(restored.top, closeTo(bounds.top, 2));
        expect(restored.width, closeTo(bounds.width, 2));
        expect(restored.height, closeTo(bounds.height, 2));
      } finally {
        await platform.restorePlayerWindow();
        await platform.setAppFullscreen(false);
        await windowManager.setAlwaysOnTop(wasTop);
        await windowManager.setBounds(bounds);
        if (wasMaximized) await windowManager.maximize();
        await platform.dispose();
      }
    },
  );
}
