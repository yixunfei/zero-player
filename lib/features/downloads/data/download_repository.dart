import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../../supervision/application/content_policy.dart';
import '../../supervision/data/content_records.dart';
import '../../supervision/domain/supervision_rules.dart';
import 'package:path/path.dart' as p;

import '../../../core/persistence/app_database.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../sources/domain/video_source.dart';
import '../domain/download_task.dart';
import '../domain/download_location.dart';

final class DownloadRepository {
  const DownloadRepository(this.db, this.root, {this.policy});
  final ContentPolicy? policy;
  bool allowed(DownloadTask task) => recordAllowed(policy, task.row);
  void requireAllowed(DownloadTask task) {
    if (!allowed(task)) throw const ContentBlocked();
  }

  final AppDatabase db;
  final Directory root;
  Stream<void> get changes => db.changesFor(const {'downloads'});
  Future<List<DownloadTask>> all() async => (await db.rows(
    'SELECT * FROM downloads ORDER BY created_at DESC',
  )).map(DownloadTask.new).toList();
  Future<DownloadTask?> find(String id) async {
    final rows = await db.rows('SELECT * FROM downloads WHERE id=?', [id]);
    return rows.isEmpty ? null : DownloadTask(rows.first);
  }

  Future<String> create(
    CatalogItem item,
    PlayLine line,
    Episode episode,
    Map<String, String> headers, {
    String? destination,
  }) async {
    policy?.requireItem(item);
    final id = stableId(
      '${DateTime.now().microsecondsSinceEpoch}|${Random.secure().nextInt(1 << 32)}',
    );
    final directory = p.join(root.path, id);
    await Directory(directory).create(recursive: true);
    await db.atomic(() async {
      await db.customStatement(
        '''INSERT INTO downloads(id,title,source_id,remote_id,line_name,episode_label,
      url,headers,status,directory,created_at,work_json) VALUES(?,?,?,?,?,?,?,?,'queued',?,?,?)''',
        [
          id,
          '${item.title} · ${episode.label}',
          item.sourceId,
          item.id,
          line.name,
          episode.label,
          episode.uri.toString(),
          jsonEncode(headers),
          directory,
          DateTime.now().millisecondsSinceEpoch,
          jsonEncode(contentRecord(item)),
        ],
      );
      if (destination != null) {
        await db.customStatement(
          'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
          ['download_output:$id', destination],
        );
      }
    }, tables: const {'downloads'});
    return id;
  }

  Future<void> setOutput(
    String id,
    String path, {
    bool saved = false,
  }) => db.atomic(() async {
    await db.customStatement(
      'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
      ['${saved ? 'download_saved' : 'download_output'}:$id', path],
    );
    if (!saved) {
      await db.customStatement('DELETE FROM app_meta WHERE key=?', [
        'download_saved:$id',
      ]);
      await db.customStatement(
        "UPDATE downloads SET status='pendingSave',error=NULL WHERE id=? AND local_path IS NOT NULL",
        [id],
      );
    }
  }, tables: const {'downloads'});

  Future<String?> output(String id, {bool saved = false}) async {
    final rows = await db.rows('SELECT value FROM app_meta WHERE key=?', [
      '${saved ? 'download_saved' : 'download_output'}:$id',
    ]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> switchLocation(
    String id,
    DownloadLocation location,
    String directory,
  ) async {
    policy?.requireItem(location.item);
    await db.write(
      "UPDATE downloads SET source_id=?,remote_id=?,line_name=?,url=?,headers=?,directory=?,completed=0,total=0,bytes=0,local_path=NULL,status='queued',error=? WHERE id=?",
      [
        location.item.sourceId,
        location.item.id,
        location.line.name,
        location.episode.uri.toString(),
        jsonEncode(location.headers),
        directory,
        '已自动换源，正在重新下载整集',
        id,
      ],
    );
    await db.write('UPDATE downloads SET work_json=? WHERE id=?', [
      jsonEncode(contentRecord(location.item)),
      id,
    ]);
  }

  Future<void> status(String id, DownloadStatus status, {String? error}) =>
      db.write('UPDATE downloads SET status=?,error=? WHERE id=?', [
        status.name,
        error,
        id,
      ]);
  Future<void> progress(String id, int completed, int total, int bytes) =>
      db.write('UPDATE downloads SET completed=?,total=?,bytes=? WHERE id=?', [
        completed,
        total,
        bytes,
        id,
      ]);
  Future<void> complete(String id, String localPath) => db.write(
    "UPDATE downloads SET status='complete',local_path=?,error=NULL WHERE id=?",
    [localPath, id],
  );
  Future<void> cacheComplete(String id, String localPath) => db.write(
    "UPDATE downloads SET local_path=?,status=CASE WHEN EXISTS(SELECT 1 FROM app_meta WHERE key='download_output:'||downloads.id) AND NOT EXISTS(SELECT 1 FROM app_meta WHERE key='download_saved:'||downloads.id) THEN 'pendingSave' ELSE 'complete' END,error=NULL WHERE id=?",
    [localPath, id],
  );

  Future<void> saved(String id, String path) => db.atomic(() async {
    await db.customStatement(
      'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
      ['download_saved:$id', path],
    );
    await db.customStatement(
      "UPDATE downloads SET status='complete',error=NULL WHERE id=?",
      [id],
    );
  }, tables: const {'downloads'});

  Future<void> recover() => db.atomic(() async {
    await db.customStatement(
      "UPDATE downloads SET status='paused',error='任务已恢复，可继续下载' WHERE status IN ('running','queued') AND local_path IS NULL",
    );
    await db.customStatement(
      "UPDATE downloads SET status='pendingSave',error='缓存已完成，等待保存' WHERE local_path IS NOT NULL AND status IN ('running','queued','saving','complete') AND EXISTS(SELECT 1 FROM app_meta WHERE key='download_output:'||downloads.id) AND NOT EXISTS(SELECT 1 FROM app_meta WHERE key='download_saved:'||downloads.id)",
    );
    await db.customStatement(
      "UPDATE downloads SET status='complete',error=NULL WHERE local_path IS NOT NULL AND status IN ('running','queued','saving') AND (NOT EXISTS(SELECT 1 FROM app_meta WHERE key='download_output:'||downloads.id) OR EXISTS(SELECT 1 FROM app_meta WHERE key='download_saved:'||downloads.id))",
    );
  }, tables: const {'downloads'});
  Future<void> remove(String id) async {
    await db.write('DELETE FROM downloads WHERE id=?', [id]);
    await db.write('DELETE FROM app_meta WHERE key IN (?,?,?)', [
      'download_output:$id',
      'download_saved:$id',
      'download_publish:$id',
    ]);
  }

  Future<void> relocate(String id, Uri uri, Map<String, String> headers) =>
      db.write('UPDATE downloads SET url=?,headers=? WHERE id=?', [
        uri.toString(),
        jsonEncode(headers),
        id,
      ]);
  bool ownsPath(String path) =>
      p.isWithin(root.absolute.path, Directory(path).absolute.path);

  Future<void> deferCleanup(String directory) {
    if (!ownsPath(directory)) throw StateError('清理路径不属于下载目录');
    return db.write('INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)', [
      'download_cleanup:${stableId(directory)}',
      directory,
    ]);
  }

  Future<void> cleanupPending() async {
    final pending = await db.rows(
      "SELECT key,value FROM app_meta WHERE key GLOB 'download_cleanup:*'",
    );
    for (final row in pending) {
      final path = row['value'] as String;
      if (!ownsPath(path)) continue;
      // Never delete a location that a current task still owns.
      if ((await db.rows('SELECT id FROM downloads WHERE directory=?', [
        path,
      ])).isNotEmpty) {
        continue;
      }
      try {
        final directory = Directory(path);
        if (await directory.exists()) await directory.delete(recursive: true);
        await db.write('DELETE FROM app_meta WHERE key=?', [row['key']]);
      } on FileSystemException {
        // Keep the journal entry for a later startup (for example a locked file).
      }
    }
  }
}
