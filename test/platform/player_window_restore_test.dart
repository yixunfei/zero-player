import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/platform/platform_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'small window restores bounds and topmost while preserving application fullscreen',
    () async {
      if (!Platform.isWindows) return;
      final calls = <MethodCall>[];
      final fullscreen = <(bool, bool)>[];
      const channel = MethodChannel('window_manager');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'getBounds') {
              return {'x': 10.0, 'y': 10.0, 'width': 1100.0, 'height': 760.0};
            }
            if (call.method == 'isMaximized' ||
                call.method == 'isAlwaysOnTop') {
              return false;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final platform = PlatformServices(
        applyFullscreen: (app, player) async => fullscreen.add((app, player)),
      );
      await platform.setAppFullscreen(true);
      await platform.fullscreen(true);
      await platform.pictureInPicture();
      expect(platform.smallWindow, isTrue);
      await Future.wait([
        platform.restorePlayerWindow(),
        platform.restorePlayerWindow(),
      ]);
      expect(platform.smallWindow, isFalse);
      expect(platform.appFullscreen.value, isTrue);
      expect(fullscreen.last, (true, false));
      expect(calls.where((c) => c.method == 'setAlwaysOnTop').length, 2);
      expect(calls.where((c) => c.method == 'setBounds').length, 2);
      await platform.dispose();
    },
  );

  test(
    'failed bounds restoration can be retried without losing fullscreen state',
    () async {
      if (!Platform.isWindows) return;
      const channel = MethodChannel('window_manager');
      var boundsWrites = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getBounds') {
              return {'x': 10.0, 'y': 10.0, 'width': 1100.0, 'height': 760.0};
            }
            if (call.method == 'isMaximized' ||
                call.method == 'isAlwaysOnTop') {
              return false;
            }
            if (call.method == 'setBounds' && ++boundsWrites == 2) {
              throw PlatformException(code: 'failed');
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final calls = <(bool, bool)>[];
      final platform = PlatformServices(
        applyFullscreen: (app, player) async => calls.add((app, player)),
      );
      await platform.setAppFullscreen(true);
      await platform.pictureInPicture();
      await expectLater(
        platform.restorePlayerWindow(),
        throwsA(isA<PlatformException>()),
      );
      expect(platform.smallWindow, isTrue);
      expect(calls.last, (true, false));
      await platform.restorePlayerWindow();
      expect(platform.smallWindow, isFalse);
      expect(calls.last, (true, false));
      await platform.dispose();
    },
  );
}
