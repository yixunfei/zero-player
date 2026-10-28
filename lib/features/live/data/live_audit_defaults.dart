import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/live_channel.dart';
import '../../../core/persistence/app_database.dart';

/// A dated packaged audit applies only to identical, previously unconfigured rows.
final class LiveAuditDefaults {
  LiveAuditDefaults(this.load);
  factory LiveAuditDefaults.bundled() => LiveAuditDefaults(
    () => rootBundle.loadString('assets/live_channel_audit.json'),
  );
  final Future<String> Function() load;
  Future<Map<String, Map>>? _data;
  Future<Map<String, Map>> get entries => _data ??= _read();
  Future<Map<String, Map>> _read() async {
    final data = jsonDecode(await load()) as Map;
    return {
      for (final row in data['results'] as List)
        (row as Map)['id'] as String: row,
    };
  }

  Future<void> apply(
    AppDatabase db,
    List<LiveChannel> channels,
    Map<String, Map> rows,
  ) async {
    for (final c in channels) {
      final row = rows[c.id];
      if (row == null || row['signature'] != c.urls.join('|')) continue;
      await db.customStatement('INSERT OR IGNORE INTO app_meta VALUES(?,?)', [
        'live_state:${c.id}',
        jsonEncode({
          for (final key in [
            'availability',
            'checkedAt',
            'latencyMs',
            'message',
            'preferredUrl',
            'resolution',
            'languages',
            'signature',
          ])
            key: row[key],
          'enabled': row['availability'] != 'unavailable',
        }),
      ]);
    }
  }
}
