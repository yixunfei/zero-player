import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/sources/domain/source_duplicates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('deduplicate explicitly selected database after its backup', () async {
    const path = String.fromEnvironment('SOURCE_DATABASE');
    const backup = String.fromEnvironment('SOURCE_BACKUP');
    if (path.isEmpty ||
        backup.isEmpty ||
        !File(path).existsSync() ||
        !File(backup).existsSync() ||
        File(path).absolute.path == File(backup).absolute.path) {
      throw StateError('Supply SOURCE_DATABASE and its separate SOURCE_BACKUP');
    }
    final db = AppDatabase(File(path));
    try {
      final repository = SourceRepository(db);
      final before = await repository.all(includeSuppressed: true);
      final replacements = await repository.deduplicate();
      final visible = await repository.all();
      final after = await repository.all(includeSuppressed: true);
      expect(after.length, before.length);
      expect(duplicateSourceGroups(visible), isEmpty);
      // ignore: avoid_print
      print({
        'recordsPreserved': after.length,
        'duplicatesArchived': replacements.length,
        'visible': visible.length,
        'enabledVisible': visible.where((s) => s.enabled).length,
        'possiblyInvalidEnabled': visible
            .where((s) => s.enabled && s.possiblyInvalid)
            .length,
      });
    } finally {
      await db.close();
    }
  });
}
