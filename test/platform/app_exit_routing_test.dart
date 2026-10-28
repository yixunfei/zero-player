import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/platform/desktop_lifecycle.dart';
import 'package:zero_player/core/platform/platform_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('window_manager');
  late PlatformServices platform;
  late DesktopLifecycle desktop;
  late List<String> calls;

  setUp(() async {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'isFullScreen') return true;
      return null;
    });
    desktop = DesktopLifecycle(File('unused-exit-window.json'));
    platform = PlatformServices()..desktop = desktop;
    await desktop.initialize();
    desktop.shutdown = () async {
      calls.add('shutdown');
      desktop.dispose();
    };
  });
  tearDown(() async {
    await platform.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'framework exit destroys after shutdown removes the window listener',
    () async {
      final response = await platform.requestAppExit(() async {
        fail('Desktop lifecycle must own service shutdown');
      });
      expect(response, AppExitResponse.cancel);
      expect(calls.indexOf('shutdown'), lessThan(calls.indexOf('destroy')));
      expect(calls.where((call) => call == 'destroy'), hasLength(1));
      await platform.requestAppExit(() async {});
      expect(calls.where((call) => call == 'destroy'), hasLength(1));
    },
  );

  test('framework exit keeps active radio alive in the tray', () async {
    desktop.keepInTray = () => true;
    desktop.hideToTray = () async => calls.add('hide');
    expect(await platform.requestAppExit(() async {}), AppExitResponse.cancel);
    expect(calls, contains('hide'));
    expect(calls, isNot(contains('shutdown')));
    expect(calls, isNot(contains('destroy')));
  });

  test(
    'platforms without a desktop lifecycle complete normal shutdown',
    () async {
      platform.desktop = null;
      desktop.dispose();
      expect(
        await platform.requestAppExit(() async {
          calls.add('fallback');
        }),
        AppExitResponse.exit,
      );
      expect(calls.last, 'fallback');
      expect(calls, isNot(contains('destroy')));
    },
  );
}
