import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_fonts.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';

void main() {
  test(
    'font, manual count and startup fullscreen survive backup and reload',
    () async {
      final db = AppDatabase.memory();
      final settings = SettingsController(db);
      final restored = SettingsController(db);
      addTearDown(() async {
        settings.dispose();
        restored.dispose();
        await db.close();
      });
      await settings.load();
      expect(settings.value.startFullscreen, isTrue);
      expect(settings.value.navigationGuideSeen, isFalse);
      expect(settings.value.font, 'xiaolai');
      expect(settings.value.manualLoadCount, 48);
      final backup = BackupService(db);
      for (final font in appFontLabels.keys) {
        await settings.update({
          'font': font,
          'startFullscreen': false,
          'navigationGuideSeen': true,
          'manualLoadCount': 96,
        });
        final saved = await backup.preview(await backup.export());
        await settings.update({
          'font': 'system',
          'startFullscreen': true,
          'navigationGuideSeen': false,
          'manualLoadCount': 24,
        });
        await backup.restore(saved);
        await restored.load();
        expect(restored.value.font, font);
        expect(restored.value.startFullscreen, isFalse);
        expect(restored.value.navigationGuideSeen, isTrue);
        expect(restored.value.manualLoadCount, 96);
      }
      final invalid = jsonDecode(await backup.export()) as Map;
      invalid['tables']['settings'] = [
        {'key': 'manualLoadCount', 'value': '241'},
      ];
      await expectLater(
        backup.preview(jsonEncode(invalid)),
        throwsFormatException,
      );
    },
  );
}
