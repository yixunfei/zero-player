import 'dart:convert';
import '../../../core/persistence/app_database.dart';
import '../domain/source_diagnostics.dart';

final class SourceDiagnosticsStore {
  const SourceDiagnosticsStore(this.db);
  final AppDatabase db;

  Future<void> save(
    String id,
    SourceDiagnostics result, {
    bool applyPolicy = false,
  }) => db.atomic(() async {
    final exists = await db.rows('SELECT id FROM sources WHERE id=?', [id]);
    if (exists.isEmpty) return;
    await db.customStatement('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      'source_diagnostic:$id',
      jsonEncode(result.toJson()),
    ]);
    if (!applyPolicy) return;
    if (result.state == 'missingDomain') {
      await db.customStatement(
        'UPDATE source_overrides SET enabled=0 WHERE source_id=?',
        [id],
      );
    } else if (result.state == 'available') {
      await db.customStatement(
        'UPDATE source_overrides SET enabled=1 WHERE source_id=? AND suppressed=0',
        [id],
      );
    } else if (result.state == 'unavailable' ||
        result.state == 'inconclusive') {
      await db.customStatement(
        'UPDATE source_overrides SET enabled=0 WHERE source_id=?',
        [id],
      );
    }
  }, tables: const {'app_meta', 'source_overrides'});
}
