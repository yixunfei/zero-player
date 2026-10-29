import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/persistence/installation_metadata.dart';
import 'package:zero_player/core/persistence/schema.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import 'package:zero_player/features/supervision/application/installation_access.dart';
import 'package:zero_player/features/supervision/application/supervision_controller.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/supervision_fixture.dart';

void main() {
  _installationTests();
  _verificationTests();
  _protectionTests();
  _backupTests();
}

void _installationTests() {
  test(
    'fresh installations prompt once and persist independent adult consent',
    () async {
      final db = AppDatabase.memory();
      final access = InstallationAccess(
        db,
        verifyPassword: (input) async => input == 'fixture',
      );
      await access.load();
      expect(access.introductionSeen, isFalse);
      expect(access.adultVerified, isFalse);
      expect(access.protectContentFilter, isFalse);
      await access.finishIntroduction();
      expect(access.adultVerified, isFalse);
      await access.verifyAdultPassword('fixture');
      await access.close();
      final restarted = InstallationAccess(db);
      await restarted.load();
      expect(restarted.introductionSeen, isTrue);
      expect(restarted.adultVerified, isTrue);
      await restarted.verifyAdultPassword('not checked after success');
      await restarted.close();
      await db.close();
    },
  );
  test('v2 upgrade is exempt without changing existing settings', () async {
    final root = await Directory.systemTemp.createTemp('install-upgrade-');
    final file = File('${root.path}/legacy.sqlite');
    final raw = sqlite3.open(file.path);
    for (final sql in schemaStatements) {
      raw.execute(sql);
    }
    raw.execute('INSERT INTO settings VALUES (?,?)', ['filterAdult', 'false']);
    raw.execute('PRAGMA user_version=2');
    raw.close();
    final db = AppDatabase(file);
    final access = InstallationAccess(db);
    try {
      await access.load();
      expect(access.introductionSeen, isTrue);
      expect(access.adultVerified, isTrue);
      expect(access.protectContentFilter, isFalse);
      expect(
        (await db.rows('SELECT value FROM settings')).single['value'],
        'false',
      );
      expect((await db.rows('PRAGMA user_version')).single['user_version'], 3);
    } finally {
      await access.close();
      await db.close();
      await root.delete(recursive: true);
    }
  });
  test(
    'corrupted local authorization cannot silently unlock filtering',
    () async {
      final db = AppDatabase.memory();
      await db.write('UPDATE app_meta SET value=? WHERE key=?', [
        '{}',
        installationAccessKey,
      ]);
      final access = InstallationAccess(db);
      await expectLater(access.load(), throwsFormatException);
      expect(access.requireAdultAccess, throwsFormatException);
      await access.close();
      await db.close();
    },
  );
}

void _verificationTests() {
  test(
    'wrong attempts and throttle survive restart and introduction completion',
    () async {
      final db = AppDatabase.memory();
      var now = DateTime.utc(2026, 10, 29);
      var checks = 0;
      Future<bool> verify(String input) async {
        checks++;
        return input == 'fixture';
      }

      var access = InstallationAccess(
        db,
        verifyPassword: verify,
        clock: () => now,
      );
      for (var i = 0; i < 5; i++) {
        await expectLater(
          access.verifyAdultPassword('wrong'),
          throwsFormatException,
        );
      }
      await access.finishIntroduction();
      await access.close();
      access = InstallationAccess(db, verifyPassword: verify, clock: () => now);
      await expectLater(
        access.verifyAdultPassword('fixture'),
        throwsFormatException,
      );
      expect(checks, 5);
      now = now.add(const Duration(seconds: 31));
      await access.verifyAdultPassword('fixture');
      expect(access.adultVerified, isTrue);
      await access.close();
      await db.close();
    },
  );
  test('failed persistence never grants adult access', () async {
    final db = AppDatabase.memory();
    final access = InstallationAccess(db, verifyPassword: (_) async => true);
    await access.load();
    await db.close();
    await expectLater(access.verifyAdultPassword('fixture'), throwsA(anything));
    expect(access.adultVerified, isFalse);
    expect(access.requireAdultAccess, throwsFormatException);
    await access.close();
  });
}

void _protectionTests() {
  test(
    'content protection defaults off, requires credentials to change and revokes sessions',
    () async {
      final db = AppDatabase.memory();
      late InstallationAccess access;
      final guard = SupervisionController(
        db,
        hasher: TestCredentialHasher(),
        protectContentFilter: () => access.protectContentFilter,
      );
      access = InstallationAccess(
        db,
        authorizeProtectionChange: () =>
            guard.require(SensitiveOperation.supervision),
        onProtectionChanged: guard.invalidatePermissions,
      );
      await guard.load();
      await access.load();
      await guard.saveCredentials(
        await guard.prepareCredentials('fixture-password'),
      );
      expect(guard.needsPassword(SensitiveOperation.contentFilter), isFalse);
      final session = guard.createSession(SensitiveOperation.contentFilter);
      await expectLater(
        access.setContentFilterProtection(true),
        throwsFormatException,
      );
      await guard.execute(
        SensitiveOperation.supervision,
        () => access.setContentFilterProtection(true),
        password: 'fixture-password',
      );
      expect(guard.needsPassword(SensitiveOperation.contentFilter), isTrue);
      await expectLater(session.run(() async {}), throwsFormatException);
      await guard.execute(
        SensitiveOperation.supervision,
        () => guard.setEnabled(false),
        password: 'fixture-password',
      );
      expect(guard.needsPassword(SensitiveOperation.contentFilter), isFalse);
      await expectLater(
        access.setContentFilterProtection(false),
        throwsFormatException,
      );
      session.close();
      await access.close();
      await guard.close();
      await db.close();
    },
  );
  test(
    'AppServices requires configured supervision for policy changes',
    () async {
      final root = await Directory.systemTemp.createTemp('access-wiring-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      try {
        await services.supervision.load();
        await services.settings.load();
        await expectLater(
          services.installationAccess.setContentFilterProtection(true),
          throwsFormatException,
        );
        await expectLater(
          services.settings.update({'filterAdult': false}),
          throwsFormatException,
        );
        expect(services.settings.value.filterAdult, isTrue);
      } finally {
        await services.close();
        await root.delete(recursive: true);
      }
    },
  );
}

void _backupTests() {
  test(
    'backup cannot transfer unlock or change content protection policy',
    () async {
      final db = AppDatabase.memory();
      final access = InstallationAccess(db, verifyPassword: (_) async => true);
      await access.load();
      final backup = BackupService(
        db,
        authorizeAdultDisable: access.requireAdultAccess,
      );
      final raw = jsonDecode(await backup.export()) as Map;
      expect(raw['tables']['app_meta'], isEmpty);
      raw['tables']['settings'] = [
        {'key': 'filterAdult', 'value': 'false'},
      ];
      final preview = await backup.preview(jsonEncode(raw));
      await expectLater(backup.restore(preview), throwsFormatException);
      await access.verifyAdultPassword('fixture');
      await access.setContentFilterProtection(true);
      await backup.restore(preview);
      final restarted = InstallationAccess(db);
      await restarted.load();
      expect(restarted.adultVerified, isTrue);
      expect(restarted.protectContentFilter, isTrue);
      raw['tables']['app_meta'] = [
        {'key': installationAccessKey, 'value': upgradedInstallationAccess},
      ];
      await expectLater(backup.preview(jsonEncode(raw)), throwsFormatException);
      await restarted.close();
      await access.close();
      await db.close();
    },
  );
}
