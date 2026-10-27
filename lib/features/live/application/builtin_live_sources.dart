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

  Future<List<Map>> _entries() async =>
      ((jsonDecode(await rootBundle.loadString('assets/live_candidates.json'))
                  as Map)['lists']
              as List)
          .cast<Map>();

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
        final enabled = defaults[entry['url']] ?? true;
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
              (!onlyMissing || rows[e['url']]!['snapshot'] == null),
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
