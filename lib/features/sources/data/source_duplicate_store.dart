import 'dart:convert';
import '../../../core/persistence/app_database.dart';
import '../domain/source_duplicates.dart';
import '../domain/video_source.dart';

final class SourceDuplicateStore {
  const SourceDuplicateStore(this.db);
  final AppDatabase db;

  /// Call inside the repository transaction. Distinct APIs keep their history.
  Future<Map<String, String>> consolidate(
    List<VideoSource> sources, {
    Set<String> preferred = const {},
  }) async {
    final replacements = <String, String>{};
    for (final group in duplicateSourceGroups(sources)) {
      group.sort((a, b) {
        if (preferred.contains(a.id) != preferred.contains(b.id)) {
          return preferred.contains(a.id) ? -1 : 1;
        }
        return compareDuplicateSources(a, b);
      });
      final keep = group.first;
      if (group.any((s) => s.favorite)) {
        await db.customStatement(
          'INSERT OR REPLACE INTO app_meta VALUES(?,?)',
          ['source_favorite:${keep.id}', 'true'],
        );
      }
      await db.customStatement('DELETE FROM app_meta WHERE key=?', [
        'source_duplicate:${keep.id}',
      ]);
      for (final duplicate in group.skip(1)) {
        await _archive(duplicate, keep);
        replacements[duplicate.id] = keep.id;
      }
    }
    return replacements;
  }

  Future<void> _archive(VideoSource duplicate, VideoSource keep) async {
    await db.customStatement(
      'UPDATE source_overrides SET suppressed=1 WHERE source_id=?',
      [duplicate.id],
    );
    await db.customStatement('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      'source_duplicate:${duplicate.id}',
      jsonEncode({'keep': keep.id, 'at': DateTime.now().toIso8601String()}),
    ]);
    await db.customStatement(
      "UPDATE settings SET value=? WHERE key='homeChannel' AND value=?",
      [jsonEncode(keep.id), jsonEncode(duplicate.id)],
    );
  }

  Future<String> preferredId(String id) async {
    final visited = <String>{};
    var current = id;
    while (current.isNotEmpty && visited.add(current)) {
      final rows = await db.rows(
        'SELECT o.suppressed,m.value FROM source_overrides o '
        'LEFT JOIN app_meta m ON m.key=? WHERE o.source_id=?',
        ['source_duplicate:$current', current],
      );
      if (rows.isEmpty || rows.single['suppressed'] != 1) return current;
      try {
        final record = jsonDecode(rows.single['value'] as String) as Map;
        final next = record['keep'];
        if (next is! String || next == current) return current;
        current = next;
      } catch (_) {
        return current;
      }
    }
    return id;
  }
}
