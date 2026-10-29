import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/supervision/application/installation_access.dart';
import 'package:zero_player/features/supervision/application/supervision_controller.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/supervision_fixture.dart';

void main() {
  test(
    'queued protection write rechecks an expired supervision grant',
    () async {
      final db = AppDatabase.memory();
      final guard = SupervisionController(db, hasher: TestCredentialHasher());
      final authorized = Completer<void>();
      var observe = false;
      final access = InstallationAccess(
        db,
        authorizeProtectionChange: () {
          guard.require(SensitiveOperation.supervision);
          if (observe && !authorized.isCompleted) authorized.complete();
        },
      );
      await guard.load();
      await access.load();
      await guard.saveCredentials(
        await guard.prepareCredentials('fixture-password'),
      );
      await guard.execute(
        SensitiveOperation.supervision,
        () => access.setContentFilterProtection(true),
        password: 'fixture-password',
      );
      final session = await guard.execute(
        SensitiveOperation.supervision,
        () async => guard.createSession(SensitiveOperation.supervision),
        password: 'fixture-password',
      );
      final entered = Completer<void>(), release = Completer<void>();
      final blocking = db.transaction(() async {
        await db.rows('SELECT 1');
        entered.complete();
        await release.future;
      });
      await entered.future;
      observe = true;
      final change = session.run(
        () => access.setContentFilterProtection(false),
      );
      final rejected = expectLater(change, throwsFormatException);
      await authorized.future;
      guard.invalidatePermissions();
      release.complete();
      await blocking;
      await rejected;
      expect(access.protectContentFilter, isTrue);
      final reloaded = InstallationAccess(db);
      await reloaded.load();
      expect(reloaded.protectContentFilter, isTrue);
      session.close();
      await reloaded.close();
      await access.close();
      await guard.close();
      await db.close();
    },
  );
}
