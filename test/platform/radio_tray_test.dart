import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/platform/desktop_lifecycle.dart';
import 'package:zero_player/core/platform/desktop_radio_tray.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/radio/application/radio_controller.dart';
import '../../test_support/fake_player_engine.dart';

final messenger =
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
const trayChannel = MethodChannel('zero_player/radio_tray');
const windowChannel = MethodChannel('window_manager');
late FakePlayerEngine engine;
late RadioController radio;
late DesktopLifecycle desktop;
late DesktopRadioTray tray;
late List<String> calls;
var failHide = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_initialize);
  tearDown(_dispose);
  test('window close hides in tray without stopping active radio', () async {
    await desktop.closeWindow();
    expect(calls, contains('tray:hide'));
    expect(calls, isNot(contains('shutdown')));
    expect(calls, isNot(contains('window:destroy')));
    expect(engine.snapshot.playing, isTrue);
    await tray.show();
    expect(calls.last, 'tray:show');
  });
  test(
    'tray registration failure does not silently exit and close can retry',
    () async {
      failHide = true;
      await expectLater(
        desktop.closeWindow(),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, isNot(contains('shutdown')));
      expect(engine.snapshot.playing, isTrue);
      failHide = false;
      await desktop.closeWindow();
      expect(calls.where((call) => call == 'tray:hide'), hasLength(2));
    },
  );
  test(
    'explicit tray exit bypasses residency and disposes before destroying',
    () async {
      await desktop.closeWindow();
      await desktop.closeWindow(force: true);
      expect(radio.active, isFalse);
      expect(
        calls.indexOf('shutdown'),
        lessThan(calls.indexOf('window:destroy')),
      );
      expect(
        calls.indexOf('tray:dispose'),
        lessThan(calls.indexOf('window:destroy')),
      );
    },
  );
  test(
    'without active playback normal close keeps its original exit behavior',
    () async {
      await radio.stop();
      await tray.update();
      await desktop.closeWindow();
      expect(calls, contains('shutdown'));
      expect(calls, contains('window:destroy'));
      expect(calls, isNot(contains('tray:hide')));
    },
  );
}

Future<void> _initialize() async {
  calls = [];
  failHide = false;
  engine = FakePlayerEngine();
  radio = RadioController(() => engine);
  desktop = DesktopLifecycle(File('unused-window.json'));
  tray = DesktopRadioTray(radio, desktop);
  messenger.setMockMethodCallHandler(windowChannel, (call) async {
    calls.add('window:${call.method}');
    if (call.method == 'isFullScreen') return true;
    return null;
  });
  messenger.setMockMethodCallHandler(trayChannel, (call) async {
    calls.add('tray:${call.method}');
    if (call.method == 'hide' && failHide) {
      throw PlatformException(code: 'unavailable');
    }
    return null;
  });
  desktop.shutdown = () async {
    calls.add('shutdown');
    await tray.dispose();
    await radio.close();
  };
  await tray.initialize();
  await radio.select(
    LiveChannel(
      id: 'radio',
      listId: 'test',
      name: '电台',
      urls: [Uri.parse('https://media.test/radio.mp3')],
    ),
  );
  await Future<void>.delayed(Duration.zero);
  await tray.update();
}

Future<void> _dispose() async {
  await tray.dispose();
  await radio.close();
  desktop.dispose();
  messenger.setMockMethodCallHandler(windowChannel, null);
  messenger.setMockMethodCallHandler(trayChannel, null);
}
