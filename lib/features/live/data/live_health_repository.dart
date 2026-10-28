import 'dart:convert';
import '../../../core/persistence/app_database.dart';
import '../domain/live_channel.dart';
import '../domain/live_health.dart';

/// Personal enable choices and probe results survive playlist refreshes.
final class LiveHealthRepository {
  const LiveHealthRepository(this.db);
  final AppDatabase db;
  Future<void> setEnabled(Iterable<String> ids, bool enabled) =>
      db.atomic(() async {
        for (final id in ids.toSet()) {
          await _patch(id, {'enabled': enabled, if (enabled) 'removed': false});
        }
      });
  Future<void> setRemoved(Iterable<String> ids, bool removed) =>
      db.atomic(() async {
        for (final id in ids.toSet()) {
          await _patch(id, {'removed': removed, if (removed) 'enabled': false});
        }
      });
  Future<void> record(LiveChannel channel, LiveHealth result) => db.atomic(
    () => _patch(channel.id, {
      'availability': result.availability.name,
      'checkedAt': DateTime.now().millisecondsSinceEpoch,
      'latencyMs': result.latencyMs,
      'message': result.message,
      'preferredUrl': result.preferredUrl,
      'signature': channel.urls.join('|'),
    }),
  );
  Future<void> _patch(String id, Map<String, Object?> changes) async {
    final key = 'live_state:$id';
    final rows = await db.rows('SELECT value FROM app_meta WHERE key=?', [key]);
    Map old = {};
    try {
      if (rows.isNotEmpty) {
        old = jsonDecode(rows.first['value'] as String) as Map;
      }
    } catch (_) {
      /* Discard malformed optional state. */
    }
    await db.customStatement('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      key,
      jsonEncode({...old, ...changes}),
    ]);
  }
}
