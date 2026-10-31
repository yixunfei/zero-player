import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/network_target_policy.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import 'package:zero_player/features/settings/data/lan_access_store.dart';

void main() {
  _permissionTests();
  test('LAN grants accept only explicit private IP origins', () {
    expect(
      LanAccessStore.validate('http://[fd00::8]:8080/'),
      'http://[fd00::8]:8080',
    );
    expect(
      LanAccessStore.validate('http://192.168.1.8:8080/'),
      'http://192.168.1.8:8080',
    );
    for (final input in [
      'http://127.0.0.1:8080',
      'http://localhost',
      'http://169.254.169.254',
      'http://100.64.0.1',
      'http://0.0.0.0',
      'http://8.8.8.8',
      'http://router.local',
      'http://[::1]',
      'http://[fe80::1]',
      'http://[::ffff:192.168.1.8]',
      'http://192.168.1.8/path',
      'http://192.168.1.8?x=1',
      'http://user:pass@192.168.1.8',
      'file:///secret',
    ]) {
      expect(
        () => LanAccessStore.validate(input),
        throwsFormatException,
        reason: input,
      );
    }
  });

  test('LAN permission is exact and never grants DNS or redirect access', () {
    final target = Uri.parse('http://192.168.1.8:8080/video');
    final policy = NetworkTargetPolicy(
      allowLanOrigin: (uri) =>
          LanAccessStore.validate('http://192.168.1.8:8080') == uri.origin,
    );
    policy.validateAccess(target, originalOrigin: true);
    expect(
      () => policy.validateAccess(target, originalOrigin: false),
      throwsFormatException,
    );
    expect(
      () => policy.validateAccess(
        target.replace(port: 8081),
        originalOrigin: true,
      ),
      throwsFormatException,
    );
    expect(
      () => policy.validateAccess(
        target.replace(scheme: 'https'),
        originalOrigin: true,
      ),
      throwsFormatException,
    );
    expect(
      () => policy.validateAddress(
        InternetAddress('192.168.1.8'),
        uri: Uri.parse('https://public.example'),
      ),
      throwsFormatException,
    );
    expect(
      () => policy.validateAddress(InternetAddress('192.168.1.9'), uri: target),
      throwsFormatException,
    );
  });
}

void _permissionTests() {
  test(
    'permissions require authorization, persist locally and stay out of backups',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      var authorized = false;
      var resets = 0;
      final store = LanAccessStore(
        db,
        authorize: () {
          if (!authorized) throw StateError('Locked');
        },
        onChanged: () => resets++,
      );
      const origin = 'http://192.168.1.8:8080';
      await expectLater(store.grant(origin), throwsStateError);
      expect(store.origins, isEmpty);
      authorized = true;
      await store.grant(origin);
      expect(store.allows(Uri.parse('$origin/media')), isTrue);
      expect(resets, 1);
      final restored = LanAccessStore(db, authorize: () {}, onChanged: () {});
      await restored.load();
      expect(restored.origins, [origin]);
      final backup = await BackupService(db).export();
      expect(backup, isNot(contains(LanAccessStore.storageKey)));
      final payload = jsonDecode(backup) as Map<String, dynamic>;
      final tables = payload['tables'] as Map;
      (tables['app_meta'] as List).add({
        'key': LanAccessStore.storageKey,
        'value': '["$origin"]',
      });
      await expectLater(
        BackupService(db).preview(jsonEncode(payload)),
        throwsFormatException,
      );
      await store.revoke(origin);
      expect(store.allows(Uri.parse(origin)), isFalse);
      expect(resets, 2);
    },
  );

  test('corrupted local permission records fail closed', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.write('INSERT INTO app_meta VALUES(?,?)', [
      LanAccessStore.storageKey,
      '["http://127.0.0.1"]',
    ]);
    final store = LanAccessStore(db, authorize: () {}, onChanged: () {});
    await store.load();
    expect(store.origins, isEmpty);
  });
}
