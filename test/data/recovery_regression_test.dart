import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/persistence/schema.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';

void main() {
  _migrationTests();
  _settingsTests();
  _backupTests();
}

void _migrationTests() {
  test(
    'failed creation rolls back and can be retried without losing data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'database-recovery',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/test.sqlite');
      var raw = sqlite3.open(file.path);
      raw.execute('CREATE VIEW watch_history AS SELECT 1 AS id');
      raw.close();
      final failed = AppDatabase(file);
      await expectLater(
        failed.rows('SELECT * FROM settings'),
        throwsA(anything),
      );
      await failed.close();
      raw = sqlite3.open(file.path);
      expect(raw.select('PRAGMA user_version').single['user_version'], 0);
      expect(
        raw.select("SELECT name FROM sqlite_master WHERE name='app_meta'"),
        isEmpty,
      );
      raw.execute('DROP VIEW watch_history');
      raw.close();
      final recovered = AppDatabase(file);
      addTearDown(recovered.close);
      expect(await recovered.rows('SELECT * FROM settings'), isEmpty);
    },
  );

  test('partially applied v1 migration is completed idempotently', () async {
    final directory = await Directory.systemTemp.createTemp(
      'migration-recovery',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/test.sqlite');
    final raw = sqlite3.open(file.path);
    for (final statement in schemaStatements) {
      raw.execute(
        statement
            .replaceAll(', homepage TEXT', '')
            .replaceAll(', latency_ms INTEGER', '')
            .replaceAll(', work_json TEXT', ''),
      );
    }
    raw.execute('PRAGMA user_version = 1');
    raw.execute('INSERT INTO settings VALUES (?, ?)', ['theme', '"dark"']);
    raw.close();
    final db = AppDatabase(file);
    addTearDown(db.close);
    expect(
      (await db.rows('SELECT value FROM settings')).single['value'],
      '"dark"',
    );
    expect(
      (await db.rows('PRAGMA table_info(sources)')).map((row) => row['name']),
      contains('homepage'),
    );
    expect((await db.rows('PRAGMA user_version')).single['user_version'], 2);
  });
}

void _settingsTests() {
  test('one damaged setting cannot block valid settings or startup', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.write('INSERT INTO settings VALUES (?, ?), (?, ?), (?, ?)', [
      'cacheMiB',
      'not-json',
      'theme',
      '"dark"',
      'downloadConcurrency',
      '"bad"',
    ]);
    final settings = SettingsController(db);
    addTearDown(settings.dispose);
    await settings.load();
    expect(settings.value.theme, 'dark');
    expect(settings.value.cacheMiB, 512);
    expect(settings.value.downloadConcurrency, 2);
  });

  test(
    'concurrent setting updates preserve both changes in memory and on disk',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final settings = SettingsController(db);
      addTearDown(settings.dispose);
      await Future.wait([
        settings.update({'theme': 'dark'}),
        settings.update({'cacheMiB': 768}),
      ]);
      expect(settings.value.theme, 'dark');
      expect(settings.value.cacheMiB, 768);
      await settings.load();
      expect(settings.value.theme, 'dark');
      expect(settings.value.cacheMiB, 768);
      await expectLater(
        settings.update({'cacheMiB': 0}),
        throwsFormatException,
      );
      await settings.update({'autoplay': false});
      expect(settings.value.autoplay, isFalse);
    },
  );
}

void _backupTests() {
  test(
    'export rejects excess rows instead of producing an unrestorable file',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.write(
        'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x < ${BackupService.maxRowsPerTable + 1}) INSERT INTO search_history SELECT CAST(x AS TEXT), x FROM n',
      );
      await expectLater(BackupService(db).export(), throwsFormatException);
    },
  );
}
