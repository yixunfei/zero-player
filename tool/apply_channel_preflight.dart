import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/live_audit_defaults.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/radio/data/radio_snapshot.dart';
import 'package:zero_player/features/radio/domain/radio_subscription.dart';
import 'package:zero_player/features/supervision/application/supervision_controller.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';

/// Explicit local maintenance; requires a consistent backup taken immediately before applying.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('apply complete preflight evidence to unchanged local channels', () async {
    const target = String.fromEnvironment('PREFLIGHT_TARGET');
    const backup = String.fromEnvironment('PREFLIGHT_BACKUP');
    if (target.isEmpty ||
        backup.isEmpty ||
        target == backup ||
        !await File(backup).exists()) {
      throw StateError(
        'Explicit target and separate consistent backup are required',
      );
    }
    final db = AppDatabase(File(target));
    final supervision = SupervisionController(db);
    try {
      await supervision.load();
      final channels = await _channels(db);
      final defaults = LiveAuditDefaults(
        () => File('assets/live_channel_audit.json').readAsString(),
      );
      final rows = await defaults.entries;
      if (!defaults.passedOnly) {
        throw StateError('Complete preflight table required');
      }
      await db.atomic(
        () => defaults.apply(
          db,
          channels,
          rows,
          includeUnlisted: true,
          canEnable: supervision.allows(SensitiveOperation.channels),
        ),
        tables: const {'app_meta'},
      );
      final ids = channels.map((c) => c.id).toSet();
      final states = [
        for (final row in await db.rows(
          "SELECT key,value FROM app_meta WHERE key GLOB 'live_state:*'",
        ))
          if (ids.contains((row['key'] as String).substring(11)))
            jsonDecode(row['value'] as String) as Map,
      ];
      final counts = {
        'enabled': states.where((s) => s['enabled'] == true).length,
        'disabled': states.where((s) => s['enabled'] != true).length,
        'manualDisabled': states.where((s) => s['userDisabled'] == true).length,
        'pending': states.where((s) => s['pendingValidation'] == true).length,
        for (final state in ['responding', 'unavailable', 'inconclusive'])
          state: states.where((s) => s['availability'] == state).length,
      };
      await File('build/local-channel-preflight-applied.json').writeAsString(
        jsonEncode({
          'checkedAt': DateTime.now().toUtc().toIso8601String(),
          'channels': channels.length,
          'counts': counts,
        }),
      );
      // ignore: avoid_print
      print(
        'Applied proof to ${channels.length} local channel entries; personal disable/removal and supervision retained.',
      );
    } finally {
      await supervision.close();
      await db.close();
    }
  });
}

Future<List<LiveChannel>> _channels(AppDatabase db) async {
  final rows = await db.rows(
    'SELECT c.*,l.url AS list_url FROM live_channels c JOIN live_lists l ON l.id=c.list_id',
  );
  final result = [
    for (final row in rows)
      LiveChannel(
        id: row['id'] as String,
        listId: row['list_id'] as String,
        name: row['name'] as String,
        urls: (jsonDecode(row['urls'] as String) as List)
            .map((u) => Uri.parse(u as String))
            .toList(),
        headers: Map<String, String>.from(jsonDecode(row['headers'] as String)),
        headerOrigin: Uri.parse(row['list_url'] as String),
      ),
  ];
  for (final row in await db.rows(
    "SELECT key,value FROM app_meta WHERE key GLOB 'radio_snapshot:*'",
  )) {
    final url = Uri.parse(
      (row['key'] as String).substring('radio_snapshot:'.length),
    );
    result.addAll(
      RadioSnapshot.fromJson(
        jsonDecode(row['value'] as String) as Map,
      ).stations(RadioSubscription(name: '本地广播', url: url)),
    );
  }
  return result;
}
