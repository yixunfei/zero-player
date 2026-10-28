import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/platform/desktop_lifecycle.dart';
import 'package:zero_player/core/platform/desktop_radio_tray.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/radio/application/radio_controller.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import '../test_support/http_test_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'Windows shell tray preserves playback and restores its window',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('native-radio-tray-');
      final audio = await _silentAudio(root);
      final fixture = await HttpTestServer.start(
        (request) => serveLocalFile(request, audio, contentType: 'audio/wav'),
      );
      final engine = MediaKitEngine(videoOutput: false);
      final radio = RadioController(() => engine);
      final desktop = DesktopLifecycle(File('${root.path}/window.json'));
      final tray = DesktopRadioTray(radio, desktop);
      const channel = MethodChannel('zero_player/radio_tray');
      try {
        await windowManager.ensureInitialized();
        await desktop.initialize();
        await tray.initialize();
        await radio.setVolume(0);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Text('Radio tray integration test')),
          ),
        );
        await radio.select(
          LiveChannel(
            id: 'native-test',
            listId: 'test',
            name: '广播托盘验证',
            urls: [fixture.baseUri.resolve('radio.wav')],
          ),
        );
        await tester.pump();
        await _waitForPosition(engine, const Duration(milliseconds: 200));
        await tray.update();
        expect(
          (await channel.invokeMapMethod<String, Object?>(
            'status',
          ))!['registered'],
          isTrue,
        );
        await desktop.closeWindow();
        expect(
          (await channel.invokeMapMethod<String, Object?>('status'))!['hidden'],
          isTrue,
        );
        expect(await windowManager.isVisible(), isFalse);
        expect(engine.snapshot.playing, isTrue);
        final hiddenPosition = engine.snapshot.position;
        await _waitForPosition(
          engine,
          hiddenPosition + const Duration(milliseconds: 750),
        );
        await tray.show();
        expect(await windowManager.isVisible(), isTrue);
        expect(
          (await channel.invokeMapMethod<String, Object?>('status'))!['hidden'],
          isFalse,
        );
        await radio.stop();
        await tray.update();
        expect(
          (await channel.invokeMapMethod<String, Object?>(
            'status',
          ))!['registered'],
          isFalse,
        );
      } finally {
        await tray.show();
        await tray.dispose();
        await radio.close();
        await fixture.close();
        desktop.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}

Future<File> _silentAudio(Directory root) async {
  const sampleRate = 8000;
  const dataSize = sampleRate * 2 * 30;
  final bytes = Uint8List(44 + dataSize);
  final header = ByteData.sublistView(bytes);
  bytes.setAll(0, 'RIFF'.codeUnits);
  header.setUint32(4, 36 + dataSize, Endian.little);
  bytes.setAll(8, 'WAVEfmt '.codeUnits);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  bytes.setAll(36, 'data'.codeUnits);
  header.setUint32(40, dataSize, Endian.little);
  return File('${root.path}/radio.wav').writeAsBytes(bytes);
}

Future<void> _waitForPosition(MediaKitEngine engine, Duration target) async {
  final watch = Stopwatch()..start();
  while (engine.snapshot.position < target) {
    if (watch.elapsed > const Duration(seconds: 10)) {
      fail('Native audio did not advance to $target');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
