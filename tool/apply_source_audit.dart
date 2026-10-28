import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/application/builtin_sources.dart';
import 'package:zero_player/features/sources/application/source_curation.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';

/// Requires an explicitly supplied database and an existing maintenance backup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('apply reviewed source audit to the selected database', () async {
    const path = String.fromEnvironment('SOURCE_DATABASE');
    const backup = String.fromEnvironment('SOURCE_BACKUP');
    if (path.isEmpty ||
        backup.isEmpty ||
        !File(path).existsSync() ||
        !File(backup).existsSync()) {
      throw StateError(
        'Specify SOURCE_DATABASE and SOURCE_BACKUP before applying',
      );
    }
    final db = AppDatabase(File(path));
    try {
      final repository = SourceRepository(db);
      await BuiltinSources(repository).initialize();
      final report =
          jsonDecode(
                await File(
                  'artifacts/source-audit-2026-10-28.json',
                ).readAsString(),
              )
              as Map;
      await SourceCuration(repository).apply(report, restore: true);
      final all = await repository.all(includeSuppressed: true);
      expect(
        all
            .where((s) => s.diagnostics?.state == 'available' && !s.suppressed)
            .every((s) => s.enabled),
        isTrue,
      );
      expect(
        all
            .where((s) => s.diagnostics?.state == 'inconclusive')
            .every((s) => !s.enabled),
        isTrue,
      );
      expect(
        all
            .where((s) => s.diagnostics?.state == 'unavailable')
            .every((s) => !s.enabled),
        isTrue,
      );
      expect(
        all
            .where((s) => s.diagnostics?.state == 'missingDomain')
            .every((s) => !s.enabled),
        isTrue,
      );
      // ignore: avoid_print
      print({
        'total': all.length,
        'enabled': all.where((s) => s.enabled && !s.suppressed).length,
        'disabled': all.where((s) => !s.enabled).length,
        'removed': all.where((s) => s.suppressed).length,
        'favorite': all
            .where((s) => s.favorite)
            .map((s) => s.displayName)
            .toList(),
      });
    } finally {
      await db.close();
    }
  });
}
