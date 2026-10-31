import '../../../core/persistence/app_database.dart';

final class LocalVideoRepository {
  const LocalVideoRepository(this.db);
  final AppDatabase db;

  Future<String?> pathFor(String id) async {
    final rows = await db.rows('SELECT value FROM app_meta WHERE key=?', [
      'local_video:$id',
    ]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> remember(String id, String path) => db.atomic(() async {
    await db.customStatement(
      'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
      ['local_video:$id', path],
    );
  }, tables: const {'local_videos'});
}
