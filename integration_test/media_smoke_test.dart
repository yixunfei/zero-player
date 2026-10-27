import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/app/zero_player_app.dart';
import 'package:zero_player/features/lab/application/lab_controller.dart';

const fixtureBase = String.fromEnvironment(
  'FIXTURE_BASE',
  defaultValue: 'http://127.0.0.1:9763',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final results = <Map<String, Object>>[];
  for (final useGateway in [false, true]) {
    for (final sample in [
      'sample.mp4',
      'master.m3u8',
      'fmp4/index.m3u8',
      'aes/index.m3u8',
      'ranges/index.m3u8',
      'separate/index.m3u8',
      'sample.flv',
    ]) {
      testWidgets(
        '${useGateway ? 'gateway' : 'direct'} $sample: decode, pause, seek',
        (tester) async {
          final controller = LabController();
          await controller.initialize();
          controller.setGateway(useGateway);
          await tester.pumpWidget(ZeroPlayerApp(controller: controller));
          // Video controls may keep scheduling frames while waiting for media.
          // Waiting for a globally settled animation tree would hang this test.
          await tester.pump(const Duration(milliseconds: 300));
          try {
            final stopwatch = Stopwatch()..start();
            await controller.open('$fixtureBase/$sample');
            await tester.pump();
            await controller.engine.video.waitUntilFirstFrameRendered.timeout(
              const Duration(seconds: 20),
            );
            final firstFrameMs = stopwatch.elapsedMilliseconds;
            await waitUntil(
              () =>
                  controller.engine.player.state.position.inMilliseconds >= 500,
            );
            expect(
              controller.engine.player.state.duration.inSeconds,
              inInclusiveRange(11, 13),
            );
            expect(controller.engine.player.state.width, 640);
            expect(controller.engine.player.state.height, 360);
            final frame = await controller.engine.player.screenshot();
            expect(frame, isNotNull);
            expect(frame!.length, greaterThan(1000));
            await controller.engine.player.pause();
            await waitUntil(() => !controller.engine.player.state.playing);
            await controller.engine.seek(const Duration(seconds: 6));
            await controller.engine.player.play();
            await waitUntil(
              () =>
                  controller.engine.player.state.position.inMilliseconds >=
                  6000,
            );
            await controller.engine.setRate(1.5);
            expect(controller.engine.player.state.rate, 1.5);
            results.add({
              'platform': Platform.operatingSystem,
              'sample': sample,
              'gateway': useGateway,
              'firstFrameMs': firstFrameMs,
              'frameBytes': frame.length,
              'gatewayFailures': controller.gateway!.failures,
            });
            expect(controller.gateway!.failures, 0);
            binding.reportData = {'mediaSamples': results};
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await controller.shutdown();
          }
        },
      );
    }
  }
}

Future<void> waitUntil(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 15)) {
      fail('Timed out waiting for player state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
