import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import 'package:zero_player/features/supervision/application/supervision_controller.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/supervision_fixture.dart';

late SupervisionFixture f;

void main() {
  setUp(() {
    f = SupervisionFixture();
  });
  tearDown(() => f.close());
  _registerCases0();
  _registerCases1();
  _recoveryTests(() => f);
  _storageTests(() => f);
}

void _registerCases0() {
  test(
    'draft cancellation leaves protection unchanged and secrets are hashed',
    () async {
      await f.load();
      await expectLater(
        f.guard.prepareCredentials('short'),
        throwsFormatException,
      );
      final draft = await f.guard.prepareCredentials('safe-test-password');
      expect(f.guard.configured, isFalse);
      expect(await f.db.rows('SELECT * FROM app_meta'), isEmpty);
      await f.guard.saveCredentials(draft);
      expect(f.guard.enabled, isTrue);
      final stored = (await f.db.rows('SELECT value FROM app_meta')).toString();
      expect(stored, isNot(contains('safe-test-password')));
      expect(stored, isNot(contains(draft.recoveryCode)));
      await expectLater(
        f.authorized(
          SensitiveOperation.supervision,
          () => f.guard.saveCredentials(draft),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'grant is scoped by purpose and expires after its awaited operation',
    () async {
      await f.configure();
      expect(
        () => f.guard.require(SensitiveOperation.channels),
        throwsFormatException,
      );
      late Future<void> delayed;
      final release = Completer<void>();
      await f.authorized(SensitiveOperation.channels, () async {
        f.guard.require(SensitiveOperation.channels);
        expect(
          () => f.guard.require(SensitiveOperation.settings),
          throwsFormatException,
        );
        delayed = release.future.then(
          (_) => f.guard.require(SensitiveOperation.channels),
        );
      });
      final expired = expectLater(delayed, throwsFormatException);
      release.complete();
      await expired;
      var called = false;
      await expectLater(
        f.guard.execute(SensitiveOperation.channels, () async {
          called = true;
        }, password: 'wrong'),
        throwsFormatException,
      );
      expect(called, isFalse);
    },
  );
}

void _registerCases1() {
  test('rule changes revoke an overlapping old grant', () async {
    await f.configure();
    final ready = Completer<void>(), resume = Completer<void>();
    final old = f.authorized(SensitiveOperation.channels, () async {
      ready.complete();
      await resume.future;
      f.guard.require(SensitiveOperation.channels);
    });
    final denied = expectLater(old, throwsFormatException);
    await ready.future;
    await f.authorized(
      SensitiveOperation.supervision,
      () => f.guard.updateRules(SupervisionRules(keywords: ['blocked'])),
    );
    resume.complete();
    await denied;
  });
  test(
    'failed attempts persist across restart and throttle before hashing',
    () async {
      await f.configure();
      for (var i = 0; i < 5; i++) {
        await expectLater(
          f.guard.execute(
            SensitiveOperation.channels,
            () async {},
            password: 'wrong',
          ),
          throwsFormatException,
        );
      }
      final reloaded = SupervisionController(
        f.db,
        hasher: f.hasher,
        clock: () => f.now,
      );
      await reloaded.load();
      final count = f.hasher.verifications;
      await expectLater(
        reloaded.execute(
          SensitiveOperation.channels,
          () async {},
          password: 'safe-test-password',
        ),
        throwsFormatException,
      );
      expect(f.hasher.verifications, count);
      f.now = f.now.add(const Duration(seconds: 31));
      await reloaded.execute(SensitiveOperation.channels, () async {
        reloaded.require(SensitiveOperation.channels);
      }, password: 'safe-test-password');
      await reloaded.close();
    },
  );
}

void _recoveryTests(SupervisionFixture Function() fixture) {
  test('recovery can only rotate credentials and retains rules', () async {
    final f = fixture();
    final recovery = await f.configure();
    await f.authorized(
      SensitiveOperation.supervision,
      () => f.guard.updateRules(SupervisionRules(keywords: ['blocked'])),
    );
    await expectLater(
      f.guard.execute(
        SensitiveOperation.channels,
        () async {},
        password: recovery,
        useRecovery: true,
      ),
      throwsFormatException,
    );
    await expectLater(
      f.guard.execute(
        SensitiveOperation.supervision,
        () => f.guard.setEnabled(false),
        password: recovery,
        useRecovery: true,
      ),
      throwsFormatException,
    );
    await f.guard.execute(
      SensitiveOperation.supervision,
      () async {
        final draft = await f.guard.prepareCredentials('replacement-password');
        expect(draft.recoveryCode, isNot(recovery));
        await f.guard.saveCredentials(draft);
      },
      password: recovery,
      useRecovery: true,
    );
    expect(f.guard.rules.keywords, ['blocked']);
    expect(f.guard.enabled, isTrue);
    await expectLater(
      f.guard.execute(
        SensitiveOperation.supervision,
        () async {},
        password: recovery,
        useRecovery: true,
      ),
      throwsFormatException,
    );
    await expectLater(
      f.authorized(SensitiveOperation.channels, () async {}),
      throwsFormatException,
    );
    await f.guard.execute(
      SensitiveOperation.channels,
      () async {},
      password: 'replacement-password',
    );
  });
  test(
    'turning supervision back on requires a new password even when disabled',
    () async {
      final f = fixture();
      await f.configure();
      await f.authorized(
        SensitiveOperation.supervision,
        () => f.guard.setEnabled(false),
      );
      expect(f.guard.enabled, isFalse);
      await expectLater(f.guard.setEnabled(true), throwsFormatException);
      await f.authorized(
        SensitiveOperation.supervision,
        () => f.guard.setEnabled(true),
      );
      expect(f.guard.enabled, isTrue);
    },
  );
}

void _storageTests(SupervisionFixture Function() fixture) {
  test(
    'backup cannot export, replace or remove supervision configuration',
    () async {
      final f = fixture();
      await f.configure();
      await f.authorized(
        SensitiveOperation.supervision,
        () => f.guard.updateRules(
          SupervisionRules(keywords: ['private-block-rule']),
        ),
      );
      final backup = BackupService(
        f.db,
        authorize: () => f.guard.require(SensitiveOperation.restore),
      );
      final text = await backup.export();
      expect(text, isNot(contains(SupervisionController.storageKey)));
      expect(text, isNot(contains('private-block-rule')));
      final preview = await backup.preview(text);
      await expectLater(backup.restore(preview), throwsFormatException);
      final before = await f.db.rows('SELECT value FROM app_meta WHERE key=?', [
        SupervisionController.storageKey,
      ]);
      await f.authorized(
        SensitiveOperation.restore,
        () => backup.restore(preview),
      );
      final after = await f.db.rows('SELECT value FROM app_meta WHERE key=?', [
        SupervisionController.storageKey,
      ]);
      expect(after, before);
      expect(
        () => f.guard.require(SensitiveOperation.channels),
        throwsFormatException,
      );
    },
  );
  test('corrupted stored credentials fail closed', () async {
    final f = fixture();
    await f.db.write('INSERT INTO app_meta VALUES(?,?)', [
      SupervisionController.storageKey,
      '{broken',
    ]);
    await f.load();
    expect(f.guard.corrupted, isTrue);
    expect(f.guard.enabled, isTrue);
    expect(f.policy.textAllowed('ordinary news'), isFalse);
    await expectLater(
      f.guard.prepareCredentials('new-password'),
      throwsFormatException,
    );
  });
  test('failed persistence cannot turn off protection in memory', () async {
    final f = fixture();
    await f.configure();
    await f.db.customStatement(
      "CREATE TRIGGER deny_unlock BEFORE INSERT ON app_meta WHEN NEW.key='supervision:v1' BEGIN SELECT RAISE(ABORT,'test write failure'); END",
    );
    await expectLater(
      f.authorized(
        SensitiveOperation.supervision,
        () => f.guard.setEnabled(false),
      ),
      throwsA(anything),
    );
    expect(f.guard.enabled, isTrue);
  });
}
