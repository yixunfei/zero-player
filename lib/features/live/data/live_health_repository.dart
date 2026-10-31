import 'dart:convert';
import '../../../core/persistence/app_database.dart';
import '../domain/live_channel.dart';
import '../domain/live_health.dart';
import '../domain/channel_probe_signature.dart';

/// Personal enable choices and probe results survive playlist refreshes.
final class LiveHealthRepository {
  const LiveHealthRepository(this.db, {this.authorize, this.canEnable});
  final AppDatabase db;
  final void Function()? authorize;
  final bool Function()? canEnable;
  Future<void> setEnabled(Iterable<String> ids, bool enabled) =>
      db.atomic(() async {
        if (enabled) authorize?.call();
        for (final id in ids.toSet()) {
          await _patch(id, {
            'enabled': enabled,
            'userDisabled': !enabled,
            'autoDisabled': false,
            if (enabled) 'removed': false,
          });
        }
      }, tables: const {'app_meta'});
  Future<void> setRemoved(Iterable<String> ids, bool removed) =>
      db.atomic(() async {
        if (!removed) authorize?.call();
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
      'requestSignature': channelProbeSignature(channel),
      'pendingValidation': false,
      'verifiedUrls': result.preferredUrl == null
          ? <String>[]
          : [result.preferredUrl!],
      if (enableResponding &&
          result.availability == LiveAvailability.responding &&
          (canEnable?.call() ?? true))
        'userDisabled': false,
      if (disableUnavailable &&
          result.availability == LiveAvailability.unavailable)
        'enabled': false,
      if (disableUnavailable &&
          result.availability == LiveAvailability.unavailable)
        'autoDisabled': true,
      if (enableResponding &&
          (canEnable?.call() ?? true) &&
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
    if (changes['enabled'] == true &&
        changes['removed'] == false &&
        old['preflight'] == true &&
        (old['availability'] != 'responding' ||
            old['pendingValidation'] == true)) {
      throw const FormatException('频道需要媒体复检通过后才能恢复');
    }
    if (changes.containsKey('availability') && old['preflight'] == true) {
      final passed = changes['availability'] == 'responding';
      changes['autoDisabled'] = !passed;
      changes['enabled'] =
          passed &&
          (changes['userDisabled'] ?? old['userDisabled']) != true &&
          old['removed'] != true &&
          (canEnable?.call() ?? true);
    }
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
