import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/domain/live_health.dart';

// Run only after backup_database.py, with the player closed. Does not enable subscriptions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'apply completed live audit to current catalog',
    () async {
      const targetPath = String.fromEnvironment('LIVE_TARGET_DATABASE');
      if (targetPath.isEmpty || !File(targetPath).existsSync()) {
        throw StateError('Existing target required');
      }
      final rows = [
        for (final line in File(
          'artifacts/live-audit-20261028.jsonl',
        ).readAsLinesSync())
          jsonDecode(line) as Map,
      ];
      final auditDb = AppDatabase(File('artifacts/live-audit-20261028.sqlite'));
      final target = AppDatabase(File(targetPath));
      final http = MediaHttpClient();
      final live = LiveRepository(target, DocumentClient(http));
      final health = LiveHealthRepository(target);
      try {
        final audited = await LiveRepository(
          auditDb,
          DocumentClient(http),
        ).channels();
        final keys = {
          for (final row in rows) '${row['id']}|${row['signature']}',
        };
        if (audited
            .expand((c) => c.entries)
            .where((c) => !c.health.removed)
            .any((c) => !keys.contains('${c.id}|${c.urls.join('|')}'))) {
          throw StateError('Audit is incomplete; target was not changed');
        }
        await _importMissing(live, auditDb);
        final channels = {
          for (final c in (await live.channels()).expand((c) => c.entries))
            c.id: c,
        };
        var applied = 0, skipped = 0;
        for (final row in rows) {
          final c = channels[row['id']];
          if (c == null ||
              c.urls.join('|') != row['signature'] ||
              c.health.removed) {
            skipped++;
            continue;
          }
          await health.record(
            c,
            LiveHealth(
              availability: LiveAvailability.values.byName(
                row['availability'] as String,
              ),
              checkedAt: DateTime.fromMillisecondsSinceEpoch(
                row['checkedAt'] as int,
              ),
              latencyMs: row['latencyMs'] as int?,
              message: row['message'] as String,
              preferredUrl: row['preferredUrl'] as String?,
              resolution: row['resolution'] as String?,
              languages: List<String>.from(row['languages'] as List),
            ),
            disableUnavailable: true,
          );
          applied++;
        }
        await _copyAuditedEpg(target);
        // ignore: avoid_print
        print({
          'applied': applied,
          'skippedChangedOrRemoved': skipped,
          'integrity': await target.rows('PRAGMA integrity_check'),
        });
      } finally {
        http.close();
        await auditDb.close();
        await target.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _importMissing(LiveRepository live, AppDatabase auditDb) async {
  final existing = {for (final row in await live.lists()) row['id']: row};
  final candidates =
      jsonDecode(File('assets/live_candidates.json').readAsStringSync()) as Map;
  final builtinUrls = {for (final e in candidates['lists'] as List) e['url']};
  final lists = await auditDb.rows(
    'SELECT * FROM live_lists WHERE snapshot IS NOT NULL',
  );
  for (final list in lists) {
    // Import audited snapshots only for still-empty built-in lists.
    if (!builtinUrls.contains(list['url']) ||
        existing[list['id']]?['snapshot'] != null) {
      continue;
    }
    final headers = await auditDb.rows(
      'SELECT value FROM app_meta WHERE key=?',
      ['live_headers:${list['id']}'],
    );
    await live.importText(
      list['name'] as String,
      Uri.parse(list['url'] as String),
      list['snapshot'] as String,
      headers: headers.isEmpty
          ? const {}
          : Map<String, String>.from(
              jsonDecode(headers.single['value'] as String),
            ),
    );
  }
}

Future<void> _copyAuditedEpg(AppDatabase target) async {
  final file = File('artifacts/live-epg-review-20261028.sqlite');
  if (!file.existsSync()) return;
  final source = AppDatabase(file);
  try {
    final guides = await target.rows(
      'SELECT DISTINCT epg_url FROM live_lists WHERE epg_url IS NOT NULL',
    );
    for (final guide in guides) {
      final rows = await source.rows(
        'SELECT * FROM epg_programs WHERE source=?',
        [guide['epg_url']],
      );
      if (rows.isEmpty) continue;
      await target.atomic(() async {
        await target.customStatement(
          'DELETE FROM epg_programs WHERE source=?',
          [guide['epg_url']],
        );
        for (var offset = 0; offset < rows.length; offset += 500) {
          await target.batch((batch) {
            for (final row in rows.skip(offset).take(500)) {
              batch.customStatement(
                'INSERT INTO epg_programs VALUES(?,?,?,?,?)',
                [
                  row['source'],
                  row['channel_id'],
                  row['start_ms'],
                  row['end_ms'],
                  row['title'],
                ],
              );
            }
          });
        }
      }, tables: const {'epg_programs'});
    }
  } finally {
    await source.close();
  }
}
