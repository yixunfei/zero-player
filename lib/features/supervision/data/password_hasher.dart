import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

/// Fixed Argon2id parameters avoid untrusted stored cost values.
/// OWASP Password Storage Cheat Sheet: 19 MiB, two passes, one lane.
abstract interface class CredentialHasher {
  Future<Map<String, String>> hash(String password);
  Future<bool> verify(String password, Map<String, String> record);
  void validate(Map<String, String> record);
  String recoveryCode();
}

final class PasswordHasher implements CredentialHasher {
  const PasswordHasher();
  static const algorithm = 'argon2id-19m-2-1-v1';

  @override
  Future<Map<String, String>> hash(String password) async {
    final salt = _randomBytes(16);
    final bytes = await _derive(password, salt);
    return {
      'algorithm': algorithm,
      'salt': base64Encode(salt),
      'hash': base64Encode(bytes),
    };
  }

  @override
  Future<bool> verify(String password, Map<String, String> record) async {
    validate(record);
    final actual = await _derive(password, base64Decode(record['salt']!));
    final expected = base64Decode(record['hash']!);
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual[i] ^ expected[i];
    }
    return difference == 0;
  }

  @override
  void validate(Map<String, String> record) {
    if (record['algorithm'] != algorithm ||
        base64Decode(record['salt'] ?? '').length != 16 ||
        base64Decode(record['hash'] ?? '').length != 32) {
      throw const FormatException('监管凭据损坏，不能绕过锁定');
    }
  }

  @override
  String recoveryCode() => base64UrlEncode(_randomBytes(24));

  List<int> _randomBytes(int count) {
    final random = Random.secure();
    return List.generate(count, (_) => random.nextInt(256));
  }

  Future<List<int>> _derive(String password, List<int> salt) =>
      Isolate.run(() async {
        final key = await Argon2id(
          memory: 19456,
          iterations: 2,
          parallelism: 1,
          hashLength: 32,
        ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
        return key.extractBytes();
      });
}
