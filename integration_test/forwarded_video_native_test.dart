import 'dart:io';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/product_app.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/persistence/application_ownership.dart';
import 'package:zero_player/core/platform/platform_services.dart';
import 'package:zero_player/features/playback/presentation/player_page.dart';
import '../test_support/fixture_project.dart';
import '../test_support/native_mark_harness.dart' show nativeWidgetUntil;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'another process replaces a playing local video in the owner window',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('forward-native-');
      final owner = await ApplicationOwnership.acquire(root);
      final services = AppServices.scoped(
        root,
        AppDatabase.memory(),
        platform: PlatformServices(),
        openRequests: owner.channel.requests,
      );
      try {
        await services.supervision.load();
        await services.settings.load();
        await services.settings.update({
          'startFullscreen': false,
          'recommendation': 'off',
          'backgroundProbe': false,
          'navigationGuideSeen': true,
        });
        await services.store.initialize();
        await services.platform.initialize();
        final fixture = File(
          '${fixtureProjectRoot()}/test_support/generated/content_filter/long.mp4',
        );
        final one = await fixture.copy('${root.path}/第一个 视频.mp4');
        final two = await fixture.copy('${root.path}/第二个 视频.mp4');
        await tester.pumpWidget(
          ProviderScope(
            overrides: [servicesProvider.overrideWithValue(services)],
            child: const ProductApp(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        // First activation has no decoder or animation to supply Flutter frames.
        await windowManager.hide();
        expect(await windowManager.isVisible(), isFalse);
        for (final file in [one, two, two]) {
          if (file == two) {
            final views = find.byType(Video).evaluate();
            if (views.isNotEmpty) {
              await (views.last.widget as Video).controller.player.pause();
            }
            await _minimizeWindow();
          }
          final previousPage = find.byType(PlayerPage).evaluate().firstOrNull;
          final result = await Process.run(
            'dart.bat',
            [
              'run',
              'test_support/open_forward_probe.dart',
              root.path,
              file.path,
            ],
            workingDirectory: fixtureProjectRoot(),
            runInShell: true,
          );
          expect(result.exitCode, 0, reason: '${result.stderr}');
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (!await windowManager.isVisible() ||
              await windowManager.isMinimized()) {
            if (DateTime.now().isAfter(deadline)) {
              fail('Owner did not wake without Flutter frames');
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect(await windowManager.isVisible(), isTrue);
          expect(await windowManager.isMinimized(), isFalse);
          await nativeWidgetUntil(tester, () {
            final pages = find.byType(PlayerPage).evaluate();
            return pages.length == 1 &&
                !identical(pages.single, previousPage) &&
                (pages.single.widget as PlayerPage).request.item.title ==
                    file.uri.pathSegments.last;
          });
          await nativeWidgetUntil(tester, () {
            final views = find.byType(Video).evaluate();
            return views.isNotEmpty &&
                ((views.last.widget as Video).controller.player.state.width ??
                        0) >
                    0;
          });
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await services.close();
        await owner.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _minimizeWindow() async {
  await windowManager.minimize();
  final minimizeDeadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await windowManager.isMinimized() &&
      DateTime.now().isBefore(minimizeDeadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(await windowManager.isMinimized(), isTrue);
}
