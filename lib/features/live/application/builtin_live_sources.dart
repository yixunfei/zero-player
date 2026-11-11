import 'dart:convert';
import 'package:flutter/services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../sources/domain/video_source.dart';
import '../data/live_repository.dart';

final class BuiltinLiveSources {
  BuiltinLiveSources(this.repository);
  final LiveRepository repository;
  Future<void>? _refresh;
  final _token = CancellationToken();
  Future<void> close() async {
    _token.cancel();
    await _refresh;
  }

  late final Future<Map> _catalog = _loadCatalog();

  Future<Map> _loadCatalog() async =>
      jsonDecode(await rootBundle.loadString('assets/live_candidates.json'))
          as Map;

  Future<List<Map>> _entries() async =>
      ((await _catalog)['lists'] as List).cast<Map>();

  Future<void> initialize({bool restore = false}) async {
    final entries = await _entries();
    final report =
        jsonDecode(await rootBundle.loadString('assets/live_precheck.json'))
            as Map;
    final defaults = {
      for (final entry in report['results'] as List)
        entry['url']: entry['defaultEnabled'] == true,
    };
    await repository.db.atomic(() async {
      if (restore) repository.authorize?.call();
      for (final entry in entries) {
        final id = stableId(entry['url'] as String);
        final key = 'builtin_live:$id';
        final seen = await repository.db.rows(
          'SELECT value FROM app_meta WHERE key=?',
          [key],
        );
        if (seen.isNotEmpty && !restore) continue;
        final existing = await repository.db.rows(
          'SELECT id FROM live_lists WHERE id=?',
          [id],
        );
        if (existing.isNotEmpty && seen.isEmpty) continue;
        final enabled =
            (repository.canEnable?.call() ?? true) &&
            (defaults[entry['url']] ?? true);
        await repository.db.customStatement(
          'INSERT OR IGNORE INTO live_lists(id,name,url,error) VALUES(?,?,?,?)',
          [
            id,
            entry['name'],
            entry['url'],
            enabled ? '尚未下载频道，请刷新内置直播' : '随包本地预检未通过，默认停用；可手动检测并启用',
          ],
        );
        if (existing.isEmpty) {
          await repository.db.customStatement(
            'INSERT OR IGNORE INTO app_meta(key,value) VALUES(?,?)',
            ['live_list_enabled:$id', jsonEncode(enabled)],
          );
        }
        await repository.db.customStatement(
          'INSERT OR REPLACE INTO app_meta VALUES(?,?)',
          [key, '1'],
        );
      }
    });
    await _seedSnapshots();
    await _retireLists();
  }

  Future<void> _retireLists() async {
    final catalog = await _catalog;
    final retired = (catalog['retired'] as List? ?? []).cast<String>();
    final migration = 'builtin_live_retired:${catalog['version']}';
    await repository.db.atomic(() async {
      if ((await repository.db.rows('SELECT key FROM app_meta WHERE key=?', [
        migration,
      ])).isNotEmpty) {
        return;
      }
      for (final url in retired) {
        final id = stableId(url);
        if ((await repository.db.rows('SELECT key FROM app_meta WHERE key=?', [
          'builtin_live:$id',
        ])).isEmpty) {
          continue;
        }
        await repository.db.customStatement(
          'INSERT OR REPLACE INTO app_meta VALUES(?,?)',
          ['live_list_enabled:$id', 'false'],
        );
        await repository.db.customStatement(
          'UPDATE live_lists SET error=? WHERE id=?',
          ['已从内置精选停用，可手动启用旧订阅', id],
        );
      }
      await repository.db.customStatement('INSERT INTO app_meta VALUES(?,?)', [
        migration,
        '1',
      ]);
    });
  }

  Future<void> _seedSnapshots() async {
    final text = await rootBundle.loadString(
      'assets/catalogs/live/builtin.snapshots.json',
    );
    final snapshots = (jsonDecode(text) as Map)['lists'] as List;
    final lists = {for (final row in await repository.lists()) row['url']: row};
    for (final snapshot in snapshots.cast<Map>()) {
      final row = lists[snapshot['url']];
      if (row == null) continue;
      final id = row['id'] as String;
      final revision = snapshot['revision'] as int?;
      if (revision == null && row['snapshot'] != null) continue;
      if (revision != null) {
        final meta = await repository.db.rows(
          'SELECT key,value FROM app_meta WHERE key IN (?,?)',
          ['builtin_live:$id', 'builtin_live_curated:$id'],
        );
        if (!meta.any((r) => r['key'] == 'builtin_live:$id')) continue;
        if (row['snapshot'] != null &&
            meta.any(
              (r) =>
                  r['key'] == 'builtin_live_curated:$id' &&
                  r['value'] == '$revision',
            )) {
          continue;
        }
      }
      await repository.importText(
        snapshot['name'] as String,
        Uri.parse(snapshot['url'] as String),
        snapshot['text'] as String,
        base: Uri.parse(snapshot['base'] as String),
        headers: await headersFor(Uri.parse(snapshot['url'] as String)),
        existingOnly: true,
        verify: false,
        cancellation: _token,
        packagedAt: snapshot['updatedAt'] as int?,
        curatedRevision: revision,
      );
    }
  }

  Future<Map<String, String>> headersFor(Uri uri) async {
    for (final entry in await _entries()) {
      if (entry['url'] == uri.toString()) {
        return Map<String, String>.from(entry['headers'] as Map? ?? {});
      }
    }
    return {};
  }

  Future<void> refresh({bool onlyMissing = false}) {
    return _refresh ??= _run(onlyMissing).whenComplete(() => _refresh = null);
  }

  Future<void> _run(bool onlyMissing) async {
    final entries = await _entries();
    final rows = {for (final r in await repository.lists()) r['url']: r};
    final selected = entries
        .where(
          (e) =>
              rows.containsKey(e['url']) &&
              rows[e['url']]!['enabled'] == 1 &&
              (!onlyMissing ||
                  rows[e['url']]!['snapshot'] == null ||
                  DateTime.now().millisecondsSinceEpoch -
                          (rows[e['url']]!['updated_at'] as int? ?? 0) >
                      const Duration(hours: 24).inMilliseconds),
        )
        .toList();
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < selected.length && !_token.isCancelled) {
        final entry = selected[cursor++];
        try {
          await repository.import(
            entry['name'] as String,
            Uri.parse(entry['url'] as String),
            headers: Map<String, String>.from(entry['headers'] as Map? ?? {}),
            cancellation: _token,
            existingOnly: true,
          );
        } catch (_) {
          /* Each list keeps its last successful snapshot and error. */
        }
      }
    }

    await Future.wait(
      List.generate(selected.length.clamp(0, 2), (_) => worker()),
    );
  }
}
