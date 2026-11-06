import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/platform/platform_services.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';
import 'package:zero_player/features/settings/domain/settings_validation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zero_player/platform');
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('orientation is saved, validated and restored on player exit', () async {
    final platform = PlatformServices(
      applyFullscreen: (_, _) async {},
      applyPlayerOrientation: (mode) =>
          channel.invokeMethod<void>('setPlayerOrientation', {'mode': mode}),
    );
    for (final mode in ['system', 'landscape', 'auto']) {
      validateSetting('playerOrientation', mode);
      final settings = UserSettings.fromMap({'playerOrientation': mode});
      expect(settings.toMap()['playerOrientation'], mode);
      await platform.setPlayerOrientation(settings.playerOrientation);
    }
    await platform.restorePlayerWindow();
    expect(calls.map((c) => c.arguments['mode']), [
      'system',
      'landscape',
      'auto',
      'system',
    ]);
    expect(
      () => validateSetting('playerOrientation', 'invalid'),
      throwsFormatException,
    );
    expect(UserSettings.fromMap({}).playerOrientation, 'system');
    await platform.dispose();
  });
}
