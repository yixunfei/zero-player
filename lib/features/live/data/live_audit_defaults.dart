import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/live_channel.dart';
import '../domain/channel_probe_signature.dart';
import '../../../core/persistence/app_database.dart';

/// A dated packaged audit applies only to identical, previously unconfigured rows.
final class LiveAuditDefaults {
  LiveAuditDefaults(this.load);
  factory LiveAuditDefaults.bundled() => LiveAuditDefaults(
    () => rootBundle.loadString('assets/live_channel_audit.json'),
  );
  final Future<String> Function() load;
  Future<Map<String, Map>>? _data;
  bool passedOnly = false;
  final managedListIds = <String>{};
  Future<Map<String, Map>> get entries => _data ??= _read();
  Future<Map<String, Map>> _read() async {
    final data = jsonDecode(await load()) as Map;
    passedOnly = data['passedOnly'] == true;
    managedListIds.addAll(
      (data['managedListIds'] as List? ?? []).cast<String>(),
    );
    final result = <String, Map>{};
    for (final row in (data['results'] as List).cast<Map>()) {
      final id = row['id'] as String;
      result[id] = row;
      if (row['requestSignature'] is String) {
        result['$id|${row['requestSignature']}'] = row;
      }
    }
    return result;
  }

  Future<void> apply(
    AppDatabase db,
    List<LiveChannel> channels,
    Map<String, Map> rows, {
    bool includeUnlisted = false,
    bool canEnable = true,
  }) async {
    final states = passedOnly
        ? {
            for (final r in await db.rows(
              "SELECT key,value FROM app_meta WHERE key GLOB 'live_state:*'",
            ))
              (r['key'] as String).substring(11): r['value'],
          }
        : const <String, Object?>{};
    for (final c in channels) {
      final row = rows['${c.id}|${channelProbeSignature(c)}'] ?? rows[c.id];
      if (passedOnly &&
          (includeUnlisted || managedListIds.contains(c.listId))) {
        await _applyPreflight(db, c, row, states[c.id], canEnable);
        continue;
      }
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

  Future<void> _applyPreflight(
    AppDatabase db,
    LiveChannel c,
    Map? row,
    Object? saved,
    bool canEnable,
  ) async {
    final key = 'live_state:${c.id}';
    Map old = {};
    try {
      if (saved is String) {
        final decoded = jsonDecode(saved);
        if (decoded is Map) old = decoded;
      }
    } on FormatException {
      /* Replace malformed optional evidence. */
    }
    final signature = channelProbeSignature(c);
    final same = old['requestSignature'] == signature;
    final match = row?['requestSignature'] == signature;
    if (same &&
        old['preflight'] == true &&
        ((old['checkedAt'] is int ? old['checkedAt'] as int : 0) >=
                (row?['checkedAt'] as int? ?? 0) ||
            !match)) {
      return;
    }
    final manual =
        old['userDisabled'] == true ||
        (old['enabled'] == false &&
            old['autoDisabled'] != true &&
            old['preflight'] != true);
    final evidence = match ? _evidence(c, row!) : const <String, Object?>{};
    final passed =
        match &&
        row?['availability'] == 'responding' &&
        (evidence['verifiedUrls'] as List? ?? []).contains(
          evidence['preferredUrl'],
        );
    final next = {
      ...old,
      if (match)
        for (final field in [
          'availability',
          'checkedAt',
          'latencyMs',
          'message',
          'preferredUrl',
          'resolution',
          'languages',
          'verifiedUrls',
        ])
          field: evidence[field],
      'signature': c.urls.join('|'),
      'requestSignature': signature,
      'preflight': true,
      'userDisabled': manual,
      'enabled':
          passed &&
          !manual &&
          old['removed'] != true &&
          (old['enabled'] == true || canEnable),
      'autoDisabled': !passed && !manual,
      'pendingValidation': !match,
      if (!match) ...{
        'availability': 'unknown',
        'checkedAt': null,
        'preferredUrl': null,
        'verifiedUrls': <String>[],
        'message': '地址或请求头已更新，等待媒体复检通过',
      },
    };
    await db.customStatement('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      key,
      jsonEncode(next),
    ]);
  }

  Map<String, Object?> _evidence(LiveChannel channel, Map row) {
    final result = Map<String, Object?>.from(row);
    if (row['verifiedIndices'] is List) {
      final indices = (row['verifiedIndices'] as List).whereType<int>().where(
        (index) => index >= 0 && index < channel.urls.length,
      );
      result['verifiedUrls'] = [
        for (final index in indices) '${channel.urls[index]}',
      ];
      final preferred = row['preferredIndex'];
      result['preferredUrl'] = preferred is int && indices.contains(preferred)
          ? '${channel.urls[preferred]}'
          : null;
    }
    return result;
  }
}
