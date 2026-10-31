import '../../../core/persistence/app_database.dart';
import '../../supervision/application/content_policy.dart';
import '../../supervision/data/content_records.dart';
import '../../../core/text/display_text.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../sources/domain/video_source.dart';

final class WatchEntry {
  const WatchEntry(this.row);
  final Map<String, Object?> row;
  String get id => row['id'] as String;
  String get sourceId => row['source_id'] as String;
  String get remoteId => row['remote_id'] as String;
  String get title => displayText(row['title'] as String);
  String get poster => row['poster'] as String;
  String get line => displayText(row['line_name'] as String);
  String get episode => displayText(row['episode_label'] as String);
  Duration get position => Duration(milliseconds: row['position_ms'] as int);
  Duration get duration => Duration(milliseconds: row['duration_ms'] as int);
}

final class HistoryRepository {
  const HistoryRepository(this.db, {this.policy});
  final ContentPolicy? policy;
  final AppDatabase db;
  Stream<void> get changes =>
      db.changesFor(const {'watch_history', 'local_videos'});
  Future<List<WatchEntry>> recentWorks() async => (await db.rows(
    'SELECT * FROM (SELECT h.*, m.value AS content_record, ROW_NUMBER() OVER '
    '(PARTITION BY source_id,remote_id ORDER BY updated_at DESC) AS recent '
    "FROM watch_history h LEFT JOIN app_meta m ON m.key='content_label:'||h.source_id||':'||h.remote_id) WHERE recent=1 ORDER BY updated_at DESC LIMIT 50",
  )).where((r) => recordAllowed(policy, r)).map(WatchEntry.new).toList();
  Future<List<WatchEntry>> all() async => (await db.rows(
    "SELECT h.*,m.value AS content_record FROM watch_history h LEFT JOIN app_meta m ON m.key='content_label:'||h.source_id||':'||h.remote_id ORDER BY updated_at DESC LIMIT 500",
  )).where((r) => recordAllowed(policy, r)).map(WatchEntry.new).toList();
  Future<WatchEntry?> latest(String sourceId, String remoteId) async {
    final rows = await db.rows(
      'SELECT * FROM watch_history WHERE source_id=? AND remote_id=? ORDER BY updated_at DESC LIMIT 1',
      [sourceId, remoteId],
    );
    return rows.isEmpty ? null : WatchEntry(rows.first);
  }

  Future<void> save(
    CatalogItem item,
    PlayLine line,
    Episode episode,
    Duration position,
    Duration duration,
  ) async {
    if (duration <= Duration.zero) return;
    policy?.requireItem(item);
    await rememberContent(db, item);
    final id = stableId(
      '${item.sourceId}|${item.id}|${line.name}|${episode.label}',
    );
    await db.write(
      '''INSERT INTO watch_history(id,source_id,remote_id,title,year,poster,line_name,episode_label,
      position_ms,duration_ms,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
      title=excluded.title,poster=excluded.poster,position_ms=excluded.position_ms,
      duration_ms=excluded.duration_ms,updated_at=excluded.updated_at''',
      [
        id,
        item.sourceId,
        item.id,
        item.title,
        item.year,
        item.poster,
        line.name,
        episode.label,
        position.inMilliseconds,
        duration.inMilliseconds,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> remove(String id) =>
      db.write('DELETE FROM watch_history WHERE id=?', [id]);
  Future<void> clear() => db.write('DELETE FROM watch_history');
  Future<List<String>> searches() async =>
      (await db.rows(
            'SELECT query FROM search_history ORDER BY used_at DESC LIMIT 20',
          ))
          .map((row) => row['query'] as String)
          .where((q) => policy?.textAllowed(q) ?? true)
          .toList();
  Future<void> recordSearch(String query) => db.write(
    'INSERT OR REPLACE INTO search_history(query,used_at) VALUES(?,?)',
    [query, DateTime.now().millisecondsSinceEpoch],
  );
  Future<void> clearSearches() => db.write('DELETE FROM search_history');
}
