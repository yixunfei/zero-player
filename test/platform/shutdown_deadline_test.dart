import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/platform/close_resources.dart';
import 'package:zero_player/core/platform/desktop_lifecycle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a stuck cleanup cannot prevent later resources from closing', () async {
    var closed = false;
    await expectLater(
      closeResources([
        () => Completer<void>().future,
        () {
          closed = true;
        },
      ], stepTimeout: const Duration(milliseconds: 10)),
      throwsA(isA<TimeoutException>()),
    );
    expect(closed, isTrue);
  });

  test('window destruction proceeds after a stuck shutdown', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('window_manager');
    var destroyed = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isFullScreen') return true;
      if (call.method == 'destroy') destroyed = true;
      return null;
    });
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    final lifecycle = DesktopLifecycle(
      File('unused'),
      stepTimeout: const Duration(milliseconds: 10),
      shutdownTimeout: const Duration(milliseconds: 10),
    )..shutdown = () => Completer<void>().future;
    addTearDown(() {
      lifecycle.dispose();
      FlutterError.onError = previous;
      messenger.setMockMethodCallHandler(channel, null);
    });
    await lifecycle.closeWindow(force: true);
    expect(destroyed, isTrue);
    expect(errors.single.exception, isA<TimeoutException>());
  });
}
