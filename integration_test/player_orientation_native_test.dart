import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/playback/presentation/player_orientation_menu.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android orientation choices persist and restore the system setting',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('orientation-native-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      final results = <Map<String, Object?>>[];
      var mode = 'system';
      try {
        await services.settings.load();
        await services.platform.initialize();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (_, update) => PlayerOrientationMenu(
                    value: mode,
                    onChanged: (value) async {
                      await services.platform.setPlayerOrientation(value);
                      await services.settings.update({
                        'playerOrientation': value,
                      });
                      update(() => mode = value);
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        for (final entry in {
          'landscape': 6,
          'auto': 10,
          'system': -1,
        }.entries) {
          await tester.tap(
            find.byTooltip('屏幕方向：${playerOrientationLabels[mode]}'),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text(playerOrientationLabels[entry.key]!).last);
          for (var i = 0; i < 60 && mode != entry.key; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(mode, entry.key);
          final device = await services.platform.playbackDeviceSnapshot();
          expect(device['requestedOrientation'], entry.value);
          if (entry.key == 'landscape') {
            expect(device['configurationOrientation'], 2);
          }
          expect(services.settings.value.playerOrientation, entry.key);
          results.add({'mode': entry.key, 'device': device});
        }
        await services.platform.setPlayerOrientation('landscape');
        await services.platform.restorePlayerWindow();
        expect(
          (await services.platform
              .playbackDeviceSnapshot())['requestedOrientation'],
          -1,
        );
        expect(tester.takeException(), isNull);
        binding.reportData = {'orientationResults': results};
        debugPrint('ORIENTATION_NATIVE $results');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await services.close();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isAndroid,
  );
}
