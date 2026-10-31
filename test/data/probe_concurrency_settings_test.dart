import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';
import 'package:zero_player/features/settings/data/backup_validation.dart';

void main() {
  test(
    'independent concurrency defaults and existing choices survive persistence',
    () async {
      final db = AppDatabase.memory();
      final controller = SettingsController(db);
      addTearDown(() async {
        await controller.close();
        await db.close();
      });
      await controller.load();
      expect(controller.value.searchConcurrency, 8);
      expect(controller.value.probeConcurrency, 8);
      expect(controller.value.lineProbeConcurrency, 8);
      await controller.update({
        'searchConcurrency': 6,
        'probeConcurrency': 3,
        'lineProbeConcurrency': 16,
      });
      await controller.load();
      expect(controller.value.searchConcurrency, 6);
      expect(controller.value.probeConcurrency, 3);
      expect(controller.value.lineProbeConcurrency, 16);
      expect(
        UserSettings.fromMap({'probeConcurrency': 3}).lineProbeConcurrency,
        8,
      );
      for (final key in ['probeConcurrency', 'lineProbeConcurrency']) {
        validateBackupRecord('settings', {'key': key, 'value': '16'});
        for (final value in [0, 17]) {
          await expectLater(
            controller.update({key: value}),
            throwsFormatException,
          );
          expect(
            () => validateBackupRecord('settings', {
              'key': key,
              'value': '$value',
            }),
            throwsFormatException,
          );
        }
      }
    },
  );
}
