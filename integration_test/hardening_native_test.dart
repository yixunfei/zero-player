import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';
import 'package:zero_player/media/gateway/media_gateway.dart';
import '../test_support/http_test_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets('native safety options, controlled radio and bounded disposal', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('zero-native-security-');
    const project = String.fromEnvironment(
      'PROJECT_ROOT',
      defaultValue: 'L:/zero-player',
    );
    final fixture = await HttpTestServer.start(
      (request) => serveLocalFile(
        request,
        File(
          '$project/test_support/generated/${request.uri.pathSegments.join('/')}',
        ),
        contentType: request.uri.path.endsWith('.wav')
            ? 'audio/wav'
            : 'application/octet-stream',
      ),
    );
    final gateway = MediaGateway(
      SegmentStore(root),
      allowPrivateNetworks: true,
    );
    final engine = MediaKitEngine(videoOutput: false, gateway: gateway);
    final errors = <String>[];
    final subscription = engine.errors.listen(errors.add);
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Native security acceptance')),
        ),
      );
      await expectLater(
        engine.open(Uri.parse('file:///C:/Windows/win.ini')),
        throwsFormatException,
      );
      await expectLater(
        engine.open(Uri.parse('javascript:alert(1)')),
        throwsFormatException,
      );
      final started = Stopwatch()..start();
      await engine.open(fixture.baseUri.resolve('radio.wav'));
      final native = engine.player.platform as NativePlayer;
      debugPrint('MPV_VERSION ${await native.getProperty('mpv-version')}');
      for (final option in [
        'load-scripts',
        'config',
        'load-unsafe-playlists',
        'access-references',
        'sub-auto',
        'audio-file-auto',
        'cache-on-disk',
      ]) {
        expect(
          await native.getProperty('options/$option'),
          'no',
          reason: option,
        );
      }
      while (engine.snapshot.position < const Duration(milliseconds: 200) &&
          started.elapsed < const Duration(seconds: 10)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      started.stop();
      expect(engine.snapshot.playing, isTrue);
      expect(engine.snapshot.position, greaterThan(Duration.zero));
      expect(gateway.requests, greaterThan(0));
      expect(errors, isEmpty);
      await _checkReferenceReset(engine, fixture.baseUri);
      expect(errors, isEmpty);
      final closeWatch = Stopwatch()..start();
      await engine.dispose().timeout(const Duration(seconds: 4));
      debugPrint(
        'NATIVE_ACCEPTANCE startupMs=${started.elapsedMilliseconds} disposeMs=${closeWatch.elapsedMilliseconds} gatewayRequests=${gateway.requests}',
      );
      await engine.dispose();
    } finally {
      await subscription.cancel();
      await engine.dispose();
      await gateway.close();
      await fixture.close();
      await root.delete(recursive: true);
    }
  });
}

Future<void> _checkReferenceReset(MediaKitEngine engine, Uri base) async {
  final native = engine.player.platform as NativePlayer;
  await engine.open(base.resolve('master.m3u8'));
  expect(await native.getProperty('options/access-references'), 'yes');
  expect(await native.getProperty('options/demuxer-lavf-format'), 'hls');
  final watch = Stopwatch()..start();
  while (engine.snapshot.position < const Duration(milliseconds: 200) &&
      watch.elapsed < const Duration(seconds: 10)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(engine.snapshot.position, greaterThan(Duration.zero));
  await engine.open(base.resolve('radio.wav'));
  expect(await native.getProperty('options/access-references'), 'no');
  expect(await native.getProperty('options/demuxer-lavf-format'), '');
  debugPrint('NATIVE_REFERENCE_RESET trustedHls=yes ordinaryMedia=no');
}
