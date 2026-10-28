import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'service shutdown runs hooks before database close and is idempotent',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'service-shutdown',
      );
      addTearDown(() => directory.delete(recursive: true));
      final db = AppDatabase.memory();
      final services = AppServices.scoped(directory, db);
      var calls = 0;
      services.addCloseHook(() async {
        calls++;
        await db.rows('SELECT * FROM settings');
      });
      final first = services.close();
      final second = services.close();
      expect(identical(first, second), isTrue);
      await first;
      expect(calls, 1);
      await expectLater(db.rows('SELECT * FROM settings'), throwsA(anything));
    },
  );

  test(
    'a shutdown hook failure still closes later resources and the database',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'service-shutdown-failure',
      );
      addTearDown(() => directory.delete(recursive: true));
      final db = AppDatabase.memory();
      final services = AppServices.scoped(directory, db);
      var secondCalled = false;
      services.addCloseHook(() async => throw StateError('player save failed'));
      services.addCloseHook(() async {
        secondCalled = true;
      });
      await expectLater(services.close(), throwsStateError);
      expect(secondCalled, isTrue);
      await expectLater(db.rows('SELECT * FROM settings'), throwsA(anything));
    },
  );
}
