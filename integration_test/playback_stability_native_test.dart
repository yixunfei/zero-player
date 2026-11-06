import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/application/playback_monitor.dart';
import 'package:zero_player/features/playback/presentation/playback_surface.dart';
import 'package:zero_player/features/playback/presentation/player_orientation_menu.dart';
import 'package:zero_player/features/playback/presentation/player_transport.dart';
import 'package:zero_player/media/engine/media_kit_engine.dart';

const fixtureBase = String.fromEnvironment(
  'FIXTURE_BASE',
  defaultValue: 'http://127.0.0.1:9763',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'native decoder recovery, rotation, repeated seeks and resource snapshots',
    _stability,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _stability(WidgetTester tester) async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final root = await Directory.systemTemp.createTemp('stability-native-');
  final services = AppServices.scoped(
    root,
    AppDatabase.memory(),
    allowPrivateNetworks: true,
  );
  await services.settings.load();
  await services.supervision.load();
  await services.gateway.start();
  await services.settings.update({'autoplay': false});
  final engine = MediaKitEngine(
    isTrustedResource: services.gateway.isRegisteredResource,
    isTrustedPlaylist: services.gateway.isRegisteredPlaylist,
  );
  final player = PlaybackController(services, engine);
  final nativeLogs = engine.player.stream.log.listen((log) {
    debugPrint('STABILITY_LOG ${log.prefix} ${log.level}: ${log.text}');
  });
  final monitor = PlaybackMonitor(
    player,
    root,
    deviceSnapshot: services.platform.playbackDeviceSnapshot,
  );
  final samples = <Map<String, Object?>>[];
  final orientation = ValueNotifier('system');
  try {
    await monitor.start();
    await _mount(tester, services, engine, player, orientation);
    await _preparePlayback(tester, engine, player);
    await _cycles(
      tester,
      services,
      engine,
      player,
      monitor,
      orientation,
      samples,
    );
    final frame = await engine.screenshot();
    expect(frame, isNotNull);
    expect(frame!.length, greaterThan(1000));
    expect(services.gateway.failures, 0);
    expect(tester.takeException(), isNull);
    binding.reportData = {
      'stabilitySamples': samples,
      'diagnostics': player.diagnosticReport(),
    };
    debugPrint('STABILITY_SAMPLES $samples');
  } catch (_) {
    await _diagnose(player, engine);
    rethrow;
  } finally {
    await nativeLogs.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
    await player.close();
    await monitor.close();
    await services.close();
    orientation.dispose();
    await root.delete(recursive: true);
  }
}

Future<void> _mount(
  WidgetTester tester,
  AppServices services,
  MediaKitEngine engine,
  PlaybackController player,
  ValueNotifier<String> orientation,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, update) => ListenableBuilder(
            listenable: player,
            builder: (_, _) => PlaybackSurface(
              controller: player,
              video: Video(controller: engine.video, controls: NoVideoControls),
              title: '播放稳定性回归',
              onBack: () {},
              onOptions: () {},
              locked: false,
              onLock: (_) {},
              gestures: true,
              transport: PlayerTransport(
                controller: player,
                fullscreen: false,
                fit: BoxFit.contain,
                onFullscreen: () {},
                onOptions: () {},
                onMark: () {},
                onScreenshot: () {},
                onFit: (_) {},
                onRestoreVideo: player.restoreVideo,
                orientationControl: Platform.isAndroid
                    ? PlayerOrientationMenu(
                        value: orientation.value,
                        onChanged: (mode) async {
                          await services.platform.setPlayerOrientation(mode);
                          update(() => orientation.value = mode);
                        },
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _preparePlayback(
  WidgetTester tester,
  MediaKitEngine engine,
  PlaybackController player,
) async {
  await player.open(
    PlaybackRequest(
      CatalogItem(
        sourceId: 'fixture',
        id: 'long',
        title: '合成媒体',
        lines: [
          PlayLine('main', [
            Episode('1', Uri.parse('$fixtureBase/content_filter/long.mp4')),
          ]),
        ],
      ),
    ),
  );
  await _until(
    tester,
    () =>
        player.state.duration > const Duration(seconds: 20) &&
        player.state.position > const Duration(seconds: 1),
  );
  final continuousStart = player.state.position;
  await _until(
    tester,
    () =>
        player.state.position >
        continuousStart +
            Duration(
              seconds: const int.fromEnvironment(
                'STABILITY_CONTINUOUS_SECONDS',
                defaultValue: 28,
              ),
            ),
  );
  expect(player.error, isNull, reason: player.diagnosticReport());
  await player.seek(const Duration(seconds: 10));
  await _until(
    tester,
    () =>
        (player.state.position - const Duration(seconds: 10)).abs() <
        const Duration(seconds: 1),
  );
  await player.toggle();
  await _until(tester, () => !player.state.playing);
  await engine.setRate(1.25);
  await player.restoreVideo();
  expect(
    (engine.player.platform as NativePlayer).current.length,
    1,
    reason: 'reopening must release the previous Dart playlist entries',
  );
  await _until(
    tester,
    () =>
        !player.awaitingResume &&
        player.state.rate == 1.25 &&
        player.state.position >= const Duration(seconds: 9),
  );
  expect(player.userPaused, isTrue);
  expect(player.state.playing, isFalse);
  expect(player.state.rate, 1.25);
  expect((await engine.readVideoDiagnostics())['softwareDecoder'], isTrue);
  await player.toggle();
}

Future<void> _cycles(
  WidgetTester tester,
  AppServices services,
  MediaKitEngine engine,
  PlaybackController player,
  PlaybackMonitor monitor,
  ValueNotifier<String> orientation,
  List<Map<String, Object?>> samples,
) async {
  for (var i = 0; i < 12; i++) {
    if (Platform.isAndroid && i < 3) {
      if (find
          .byTooltip('屏幕方向：${playerOrientationLabels[orientation.value]}')
          .hitTestable()
          .evaluate()
          .isEmpty) {
        await tester.tapAt(tester.getCenter(find.byType(Video)));
        await tester.pump();
      }
      await tester.tap(
        find.byTooltip('屏幕方向：${playerOrientationLabels[orientation.value]}'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find
            .text(playerOrientationLabels[['landscape', 'auto', 'system'][i]]!)
            .last,
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    final before = player.state.position;
    await _until(
      tester,
      () => player.state.position > before + const Duration(seconds: 5),
    );
    expect(player.error, isNull, reason: player.diagnosticReport());
    await monitor.sample();
    samples.add({
      'cycle': i,
      'positionMs': player.state.position.inMilliseconds,
      'rssMiB': ProcessInfo.currentRss ~/ 1048576,
      'native': await services.platform.playbackDeviceSnapshot(),
    });
    final target = Duration(seconds: 3 + i);
    await player.seek(target);
    await _until(
      tester,
      () => (player.state.position - target).abs() < const Duration(seconds: 1),
    );
    if (i % 4 == 3) {
      await player.restoreVideo();
      await _until(
        tester,
        () => !player.awaitingResume && player.state.playing,
      );
      expect((engine.player.platform as NativePlayer).current.length, 1);
    }
  }
}

Future<void> _diagnose(PlaybackController player, MediaKitEngine engine) async {
  debugPrint('STABILITY_FAILURE ${player.diagnosticReport()}');
  final native = engine.player.platform as NativePlayer;
  for (final property in [
    'time-pos',
    'seekable',
    'core-idle',
    'pause',
    'seeking',
    'idle-active',
    'playlist-count',
    'playlist-pos',
    'eof-reached',
  ]) {
    debugPrint(
      'STABILITY_NATIVE $property=${await native.getProperty(property)}',
    );
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 35)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue);
}
