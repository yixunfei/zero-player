import 'dart:convert';
import 'dart:io';

import '../../media/cache/segment_metadata.dart';
import '../../media/cache/segment_store.dart';
import 'app_database.dart';

final class SegmentIndex implements SegmentMetadata {
  const SegmentIndex(this.db);
  final AppDatabase db;
  @override
  Future<Map<String, StoredResource>> entries() async => {
    for (final row in await db.rows(
      'SELECT * FROM segment_index ORDER BY used_at',
    ))
      row['cache_key'] as String: StoredResource(
        file: File(row['path'] as String),
        length: row['bytes'] as int,
        digest: row['digest'] as String,
        statusCode: row['status_code'] as int,
        headers: Map<String, String>.from(jsonDecode(row['headers'] as String)),
      ),
  };
  @override
  Future<void> put(String key, StoredResource value) => db.customStatement(
    '''INSERT INTO segment_index
    (cache_key,path,bytes,digest,status_code,headers,used_at) VALUES(?,?,?,?,?,?,?)
    ON CONFLICT(cache_key) DO UPDATE SET path=excluded.path,bytes=excluded.bytes,
    digest=excluded.digest,status_code=excluded.status_code,headers=excluded.headers,used_at=excluded.used_at''',
    [
      key,
      value.file.path,
      value.length,
      value.digest,
      value.statusCode,
      jsonEncode(value.headers),
      DateTime.now().millisecondsSinceEpoch,
    ],
  );
  @override
  Future<void> remove(String key) =>
      db.customStatement('DELETE FROM segment_index WHERE cache_key=?', [key]);
  @override
  Future<Set<String>> protectedKeys() async => (await db.rows(
    'SELECT DISTINCT cache_key FROM segment_references',
  )).map((r) => r['cache_key'] as String).toSet();
  @override
  Future<void> pin(String owner, String key) => db.customStatement(
    'INSERT OR IGNORE INTO segment_references VALUES(?,?)',
    [owner, key],
  );
  @override
  Future<void> unpin(String owner) => db.customStatement(
    'DELETE FROM segment_references WHERE owner=?',
    [owner],
  );
  @override
  Future<void> retainPins(String owner, Set<String> keys) =>
      db.atomic(() async {
        final rows = await db.rows(
          'SELECT cache_key FROM segment_references WHERE owner=?',
          [owner],
        );
        for (final row in rows) {
          if (!keys.contains(row['cache_key'])) {
            await db.customStatement(
              'DELETE FROM segment_references WHERE owner=? AND cache_key=?',
              [owner, row['cache_key']],
            );
          }
        }
      });
}
