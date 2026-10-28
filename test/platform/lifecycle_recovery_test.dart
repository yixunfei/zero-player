import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/platform/close_resources.dart';
import 'package:zero_player/core/platform/desktop_lifecycle.dart';
import 'package:zero_player/core/platform/platform_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'cleanup attempts every resource in order after an earlier failure',
    () async {
      final calls = <int>[];
      final error = StateError('first');
      await expectLater(
        closeResources([
          () {
            calls.add(1);
            throw error;
          },
          () async {
            calls.add(2);
            throw StateError('second');
          },
          () {
            calls.add(3);
          },
        ]),
        throwsA(same(error)),
      );
      expect(calls, [1, 2, 3]);
    },
  );

  test('failed native window destruction can be retried', () async {
    var attempts = 0;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      if (call.method == 'isFullScreen') return true;
      if (call.method == 'destroy' && ++attempts == 1) {
        throw PlatformException(code: 'transient');
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      ),
    );
    final lifecycle = DesktopLifecycle(File('unused-window.json'));
    addTearDown(lifecycle.dispose);
    await expectLater(
      lifecycle.closeWindow(),
      throwsA(isA<PlatformException>()),
    );
    await lifecycle.closeWindow();
    expect(attempts, 2);
  });

  test(
    'metered connection failures and timeouts use the conservative fallback',
    () async {
      const channel = MethodChannel('zero_player/platform');
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      expect(await PlatformServices.queryMeteredConnection(), isTrue);
      messenger.setMockMethodCallHandler(
        channel,
        (_) => Completer<bool>().future,
      );
      expect(
        await PlatformServices.queryMeteredConnection(
          timeout: const Duration(milliseconds: 5),
        ),
        isTrue,
      );
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      expect(await PlatformServices.queryMeteredConnection(), isFalse);
    },
  );
}
