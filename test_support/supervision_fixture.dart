import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/supervision/application/content_policy.dart';
import 'package:zero_player/features/supervision/application/supervision_controller.dart';
import 'package:zero_player/features/supervision/data/password_hasher.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';

/// Test double only; production always uses the fixed Argon2id implementation.
final class TestCredentialHasher implements CredentialHasher {
  int serial = 0, verifications = 0;
  @override
  Future<Map<String, String>> hash(String password) async => {
    'algorithm': 'test-only',
    'hash': sha256.convert(utf8.encode(password)).toString(),
  };
  @override
  Future<bool> verify(String password, Map<String, String> record) async {
    verifications++;
    return (await hash(password))['hash'] == record['hash'];
  }

  @override
  String recoveryCode() => 'recovery-code-${++serial}';
  @override
  void validate(Map<String, String> record) {
    if (record['algorithm'] != 'test-only' || record['hash']?.length != 64) {
      throw const FormatException('Invalid test credential');
    }
  }
}

final class SupervisionFixture {
  final db = AppDatabase.memory();
  final hasher = TestCredentialHasher();
  DateTime now = DateTime.utc(2026, 10, 28);
  late final guard = SupervisionController(
    db,
    hasher: hasher,
    clock: () => now,
  );
  late final settings = SettingsController(
    db,
    authorize: () => guard.require(SensitiveOperation.settings),
  );
  late final policy = ContentPolicy(settings, guard);
  late final sources = SourceRepository(
    db,
    policy: policy,
    authorize: () => guard.require(SensitiveOperation.channels),
    canEnable: () => guard.allows(SensitiveOperation.channels),
  );
  Future<void> load() async {
    await guard.load();
    await settings.load();
  }

  Future<String> configure() async {
    await load();
    final draft = await guard.prepareCredentials('safe-test-password');
    await guard.saveCredentials(draft);
    return draft.recoveryCode;
  }

  Future<T> authorized<T>(SensitiveOperation op, Future<T> Function() body) =>
      guard.execute(op, body, password: 'safe-test-password');
  Future<void> close() async {
    policy.dispose();
    await settings.close();
    await guard.close();
    await db.close();
  }
}
