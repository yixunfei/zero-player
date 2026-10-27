import '../../../core/persistence/app_database.dart';
import '../../sources/domain/video_source.dart';

final class SkipMark {
  const SkipMark({
    required this.id,
    required this.start,
    required this.end,
    required this.duration,
    required this.label,
    this.enabled = true,
  });
  final String id;
  final Duration start;
  final Duration end;
  final Duration duration;
  final String label;
  final bool enabled;
}

final class SkipRepository {
  const SkipRepository(this.db);
  final AppDatabase db;
  Future<List<SkipMark>> list(String workKey) async =>
      (await db.rows(
            'SELECT * FROM skip_marks WHERE work_key=? ORDER BY start_ms',
            [workKey],
          ))
          .map(
            (r) => SkipMark(
              id: r['id'] as String,
              start: Duration(milliseconds: r['start_ms'] as int),
              end: Duration(milliseconds: r['end_ms'] as int),
              duration: Duration(milliseconds: r['duration_ms'] as int),
              label: r['label'] as String,
              enabled: r['enabled'] == 1,
            ),
          )
          .toList();
  Future<void> add(
    String key,
    Duration start,
    Duration end,
    Duration duration,
    String label,
  ) async {
    if (start < Duration.zero || end <= start || end > duration) {
      throw const FormatException('片段范围不正确');
    }
    await db.write(
      'INSERT INTO skip_marks(id,work_key,start_ms,end_ms,label,duration_ms) VALUES(?,?,?,?,?,?)',
      [
        stableId('$key|$start|$end|${DateTime.now().microsecondsSinceEpoch}'),
        key,
        start.inMilliseconds,
        end.inMilliseconds,
        label,
        duration.inMilliseconds,
      ],
    );
  }

  Future<void> remove(String id) =>
      db.write('DELETE FROM skip_marks WHERE id=?', [id]);
  Future<void> edit(SkipMark mark, Duration start, Duration end, String label) {
    if (start < Duration.zero || end <= start || end > mark.duration) {
      throw const FormatException('片段范围不正确');
    }
    return db.write(
      'UPDATE skip_marks SET start_ms=?,end_ms=?,label=? WHERE id=?',
      [start.inMilliseconds, end.inMilliseconds, label, mark.id],
    );
  }

  Future<bool> workEnabled(String key) async {
    final rows = await db.rows(
      'SELECT enabled FROM skip_preferences WHERE work_key=?',
      [key],
    );
    return rows.isEmpty || rows.first['enabled'] == 1;
  }

  Future<void> setWorkEnabled(String key, bool value) => db.write(
    'INSERT OR REPLACE INTO skip_preferences VALUES(?,?)',
    [key, value ? 1 : 0],
  );
  Future<void> enable(String id, bool value) => db.write(
    'UPDATE skip_marks SET enabled=? WHERE id=?',
    [value ? 1 : 0, id],
  );
}
