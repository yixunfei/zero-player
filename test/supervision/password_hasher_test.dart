import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/supervision/data/password_hasher.dart';

void main() {
  test(
    'production Argon2id uses random salt and verifies without plaintext storage',
    () async {
      const hasher = PasswordHasher();
      final first = await hasher.hash('a-strong-test-password');
      final second = await hasher.hash('a-strong-test-password');
      expect(first['algorithm'], PasswordHasher.algorithm);
      expect(first['salt'], isNot(second['salt']));
      expect(first['hash'], isNot(second['hash']));
      expect(base64Decode(first['salt']!).length, 16);
      expect(base64Decode(first['hash']!).length, 32);
      expect(await hasher.verify('a-strong-test-password', first), isTrue);
      expect(await hasher.verify('wrong', first), isFalse);
      expect(hasher.recoveryCode(), isNot(hasher.recoveryCode()));
      expect(
        () => hasher.validate({...first, 'algorithm': 'unexpected'}),
        throwsFormatException,
      );
      expect(first.toString(), isNot(contains('a-strong-test-password')));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
