import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/data/source_diagnostics_store.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/sources/domain/source_diagnostics.dart';

void main() {
  test(
    'available sources recover while user-removed sources stay removed',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final repo = SourceRepository(db);
      final store = SourceDiagnosticsStore(db);
      final id = await repo.saveManual(
        'fixture',
        Uri.https('example.test', '/api'),
        enabled: false,
      );
      Future<void> record(String state) => store.save(
        id,
        SourceDiagnostics(state: state, checkedAt: DateTime.now()),
        applyPolicy: true,
      );
      await record('available');
      expect((await repo.find(id))!.enabled, isTrue);
      await record('inconclusive');
      expect((await repo.find(id))!.enabled, isFalse);
      expect((await repo.find(id))!.suppressed, isFalse);
      await record('cancelled');
      expect((await repo.find(id))!.enabled, isFalse);
      await record('available');
      expect((await repo.find(id))!.enabled, isTrue);
      await repo.batch([id], enabled: false, suppressed: true);
      await record('available');
      expect((await repo.find(id))!.enabled, isFalse);
      expect((await repo.find(id))!.suppressed, isTrue);
    },
  );
}
