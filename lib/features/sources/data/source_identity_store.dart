import '../../../core/persistence/app_database.dart';
import '../domain/source_identity.dart';
import '../domain/video_source.dart';

final class SourceIdentityStore {
  const SourceIdentityStore(this.db);
  final AppDatabase db;

  Future<String> resolve(String kind, Uri endpoint) async {
    final identity = sourceIdentity(kind, endpoint);
    final rows = await db.rows(
      'SELECT id,endpoint FROM sources WHERE kind=? ORDER BY manual DESC,rowid',
      [kind],
    );
    for (final row in rows) {
      if (sourceIdentity(kind, Uri.parse(row['endpoint'] as String)) ==
          identity) {
        return row['id'] as String;
      }
    }
    return stableId('$kind|$endpoint');
  }

  Future<void> consolidate() => db.atomic(() async {
    final rows = await db.rows(
      'SELECT * FROM sources ORDER BY manual DESC,rowid',
    );
    final seen = <String, String>{};
    for (final row in rows) {
      final id = row['id'] as String;
      final identity = sourceIdentity(
        row['kind'] as String,
        Uri.parse(row['endpoint'] as String),
      );
      final keep = seen[identity];
      if (keep == null) {
        seen[identity] = id;
      } else {
        await _merge(keep, id);
      }
    }
  });

  Future<void> _merge(String keep, String duplicate) async {
    await db.customStatement(
      '''INSERT OR IGNORE INTO source_memberships(subscription_id,source_id)
      SELECT subscription_id,? FROM source_memberships WHERE source_id=?''',
      [keep, duplicate],
    );
    await db.customStatement(
      '''UPDATE source_overrides SET suppressed=MAX(suppressed,COALESCE(
      (SELECT suppressed FROM source_overrides WHERE source_id=?),0))
      WHERE source_id=?''',
      [duplicate, keep],
    );
    await db.customStatement(
      '''UPDATE sources SET classification=CASE WHEN classification='adult' OR
      (SELECT classification FROM sources WHERE id=?)='adult' THEN 'adult'
      WHEN classification='unknown' THEN (SELECT classification FROM sources WHERE id=?)
      ELSE classification END WHERE id=?''',
      [duplicate, duplicate, keep],
    );
    for (final table in ['watch_history', 'downloads']) {
      await db.customStatement(
        'UPDATE $table SET source_id=? WHERE source_id=?',
        [keep, duplicate],
      );
    }
    await db.customStatement('DELETE FROM sources WHERE id=?', [duplicate]);
  }
}
