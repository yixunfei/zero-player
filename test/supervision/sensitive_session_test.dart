import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/supervision/application/supervision_controller.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/supervision_fixture.dart';

void main() {
  late SupervisionFixture f;
  setUp(() async {
    f = SupervisionFixture();
    await f.configure();
  });
  tearDown(() => f.close());
  test(
    'management session is scoped, revocable, and holds no global grant',
    () async {
      expect(
        () => f.guard.createSession(SensitiveOperation.settings),
        throwsFormatException,
      );
      final session = await f.authorized(
        SensitiveOperation.settings,
        () async => f.guard.createSession(SensitiveOperation.settings),
      );
      for (var i = 0; i < 3; i++) {
        await session.run(
          () async => f.guard.require(SensitiveOperation.settings),
        );
      }
      expect(
        () => f.guard.require(SensitiveOperation.settings),
        throwsFormatException,
      );
      await expectLater(
        session.run(() async => f.guard.require(SensitiveOperation.channels)),
        throwsFormatException,
      );
      session.close();
      await expectLater(session.run(() async {}), throwsFormatException);
    },
  );
  test('changing protection revokes an open management session', () async {
    final SensitiveSession session = await f.authorized(
      SensitiveOperation.settings,
      () async => f.guard.createSession(SensitiveOperation.settings),
    );
    await f.authorized(
      SensitiveOperation.supervision,
      () => f.guard.setEnabled(false),
    );
    await expectLater(session.run(() async {}), throwsFormatException);
  });
}
