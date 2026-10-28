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
      }, tables: const {'app_meta'});
  Future<void> setRemoved(Iterable<String> ids, bool removed) =>
      db.atomic(() async {
        for (final id in ids.toSet()) {
          await _patch(id, {'removed': removed, if (removed) 'enabled': false});
        }
      }, tables: const {'app_meta'});
  Future<void> record(
    LiveChannel channel,
    LiveHealth result, {
    bool disableUnavailable = false,
    bool enableResponding = false,
  }) => db.atomic(
    () => _patch(channel.id, {
      'availability': result.availability.name,
      'checkedAt': (result.checkedAt ?? DateTime.now()).millisecondsSinceEpoch,
      'latencyMs': result.latencyMs,
      'message': result.message,
      'preferredUrl': result.preferredUrl,
      'resolution': result.resolution,
      'languages': result.languages,
      'signature': channel.urls.join('|'),
      if (disableUnavailable &&
          result.availability == LiveAvailability.unavailable)
        'enabled': false,
      if (enableResponding &&
          result.availability == LiveAvailability.responding)
        'enabled': true,
    }),
    tables: const {'app_meta'},
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
    // An overlapping probe must never resurrect a removed entry.
    if (old['removed'] == true &&
        changes['enabled'] == true &&
        changes['removed'] != false) {
      changes.remove('enabled');
    }
    await db.customStatement('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      key,
      jsonEncode({...old, ...changes}),
    ]);
  }
}
