import '../../../core/persistence/app_database.dart';
import '../domain/video_source.dart';

final class SourcePreferences {
  const SourcePreferences(this.db);
  final AppDatabase db;

  Future<void> favorite(String id, bool value) => db.write(
    'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
    ['source_favorite:$id', value ? 'true' : 'false'],
  );

  Future<void> seedDefaults(List<VideoSource> sources) => db.atomic(() async {
    for (final source in sources) {
      if (!{
        'kanju3.com',
        'wu5mv.com',
        '360zy.com',
      }.contains(source.endpoint.host)) {
        continue;
      }
      final name = switch (source.endpoint.host) {
        'kanju3.com' => '看剧AI',
        'wu5mv.com' => '555电影',
        _ => '360资源站',
      };
      await db.customStatement(
        'UPDATE sources SET name=? WHERE id=? AND (name=? OR name=?)',
        [name, source.id, source.endpoint.host, source.endpoint.toString()],
      );
      await db.customStatement('INSERT OR IGNORE INTO app_meta VALUES(?,?)', [
        'source_favorite:${source.id}',
        'true',
      ]);
    }
  }, tables: const {'app_meta'});
}
