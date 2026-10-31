import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/live/domain/channel_probe_signature.dart';
import 'package:zero_player/features/live/data/live_playlist_parser.dart';
import 'package:zero_player/features/live/data/playlist_channels.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import 'package:zero_player/features/radio/data/radio_snapshot.dart';
import 'package:zero_player/features/radio/domain/radio_subscription.dart';
import 'package:zero_player/features/settings/data/lan_access_store.dart';
import 'audit_channel_preflight.dart' show ChannelAudit;

/// Run only against a consistent COPY created by backup_database.py.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'complete preflight of locally cached channels without modifying the original database',
    () async {
      const input = String.fromEnvironment('PREFLIGHT_DATABASE');
      if (input.isEmpty) {
        throw StateError('PREFLIGHT_DATABASE must point to a backup copy');
      }
      final db = AppDatabase(File(input));
      final lan = LanAccessStore(
        db,
        authorize: () => throw StateError('read only'),
        onChanged: () {},
      );
      await lan.load();
      final audit = ChannelAudit(
        allowLanOrigin: lan.allows,
        outputPrefix: 'local-channel-preflight',
        verifyOriginTransport: true,
      );
      try {
        await _load(audit, db);
        await _reusePublicEvidence(audit);
        await _resume(audit);
        await audit.check();
        await File('build/local-channel-preflight-full.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'checkedAt': DateTime.now().toUtc().toIso8601String(),
            'results': audit.results,
            'unreachableOrigins': audit.unreachableOrigins.toList(),
            'scope':
                'All cached live rows and radio snapshots, including disabled subscriptions; original DB untouched',
          }),
        );
      } finally {
        audit.http.close();
        audit.scheduler.close();
        await lan.close();
        await db.close();
      }
    },
    timeout: const Timeout(Duration(hours: 2)),
  );
}

Future<void> _resume(ChannelAudit audit) async {
  final file = File('build/local-channel-preflight-progress.json');
  if (!await file.exists()) return;
  final saved = jsonDecode(await file.readAsString()) as Map;
  final current = {
    for (final c in audit.channels) '${c.id}|${channelProbeSignature(c)}': c,
  };
  for (final row in (saved['results'] as List? ?? []).cast<Map>()) {
    final channel = current['${row['id']}|${row['requestSignature']}'];
    if (channel == null) continue;
    if (DateTime.now().millisecondsSinceEpoch -
            (row['checkedAt'] as int? ?? 0) >
        const Duration(hours: 24).inMilliseconds) {
      continue;
    }
    audit.results.add(Map<String, Object?>.from(row));
    for (final route in (row['routes'] as List).cast<Map>()) {
      final uri = Uri.parse(route['url'] as String);
      audit.cache[jsonEncode(['$uri', channel.headersFor(uri)])] = Future.value(
        {...Map<String, Object?>.from(route), 'checkedAt': row['checkedAt']},
      );
    }
  }
}

Future<void> _reusePublicEvidence(ChannelAudit audit) async {
  final file = File('build/channel-preflight-full.json');
  if (!await file.exists()) return;
  final public = jsonDecode(await file.readAsString()) as Map;
  final checkedAt = DateTime.tryParse(public['checkedAt'] as String? ?? '');
  if (checkedAt == null ||
      DateTime.now().toUtc().difference(checkedAt).inHours >= 24) {
    return;
  }
  final records = {
    for (final row in (public['results'] as List).cast<Map>())
      row['requestSignature']: row,
  };
  final candidates =
      (jsonDecode(await File('assets/live_candidates.json').readAsString())
              as Map)['lists']
          as List;
  final headers = {
    for (final row in candidates.cast<Map>())
      row['url']: Map<String, String>.from(row['headers'] as Map? ?? {}),
  };
  final snapshots =
      (jsonDecode(
                await File(
                  'assets/catalogs/live/builtin.snapshots.json',
                ).readAsString(),
              )
              as Map)['lists']
          as List;
  final channels = <LiveChannel>[];
  for (final snapshot in snapshots.cast<Map>()) {
    final origin = Uri.parse(snapshot['url'] as String);
    channels.addAll([
      for (final c in preparePlaylistChannels(
        parseLivePlaylist(
          snapshot['text'] as String,
          Uri.parse(snapshot['base'] as String),
          stableId('$origin'),
        ),
        const [],
        headers['$origin'] ?? {},
      ))
        LiveChannel(
          id: c.id,
          listId: c.listId,
          name: c.name,
          urls: c.urls,
          headers: c.headers,
          headerOrigin: origin,
        ),
    ]);
  }
  channels.addAll(
    RadioSnapshot.fromJson(
      jsonDecode(
            await File('assets/catalogs/radio/cn.snapshot.json').readAsString(),
          )
          as Map,
    ).stations(
      RadioSubscription(name: '内置广播', url: Uri.parse(builtinRadioUrl)),
    ),
  );
  final needed = {
    for (final c in audit.channels)
      for (final uri in c.urls) jsonEncode(['$uri', c.headersFor(uri)]),
  };
  for (final channel in channels) {
    final row = records[channelProbeSignature(channel)];
    if (row == null) continue;
    for (final route in (row['routes'] as List).cast<Map>()) {
      if (audit.allowLanOrigin?.call(Uri.parse(route['url'] as String)) ??
          false) {
        continue;
      }
      final key = jsonEncode([
        route['url'],
        channel.headersFor(Uri.parse(route['url'] as String)),
      ]);
      if (!needed.contains(key)) continue;
      audit.cache[key] = Future.value({
        ...Map<String, Object?>.from(route),
        'checkedAt': row['checkedAt'],
      });
    }
  }
  // ignore: avoid_print
  print(
    'Reusing ${audit.cache.length} exact URL/header results from the completed public audit',
  );
}

Future<void> _load(ChannelAudit audit, AppDatabase db) async {
  final rows = await db.rows(
    'SELECT c.*,l.url AS list_url,l.name AS list_name FROM live_channels c JOIN live_lists l ON l.id=c.list_id',
  );
  audit.channels.addAll([
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
        listName: row['list_name'] as String,
      ),
  ]);
  final radio = await db.rows(
    "SELECT key,value FROM app_meta WHERE key GLOB 'radio_snapshot:*'",
  );
  for (final row in radio) {
    final url = Uri.parse(
      (row['key'] as String).substring('radio_snapshot:'.length),
    );
    final snapshot = RadioSnapshot.fromJson(
      jsonDecode(row['value'] as String) as Map,
    );
    audit.channels.addAll(
      snapshot.stations(RadioSubscription(name: '本地广播快照', url: url)),
    );
  }
  // ignore: avoid_print
  print(
    'Loaded ${audit.channels.length} cached channels (${rows.length} live records, ${radio.length} radio snapshots)',
  );
}
