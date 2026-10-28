import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/request_scheduler.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/application/live_probe.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/domain/live_health.dart';

// Explicit maintenance command; all data remains in an isolated audit database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'audit current live playlists and media',
    () async {
      const path = String.fromEnvironment(
        'LIVE_AUDIT_DATABASE',
        defaultValue: 'artifacts/live-audit-20261028.sqlite',
      );
      final db = AppDatabase(File(path));
      final scheduler = RequestScheduler(globalLimit: 16, originLimit: 4);
      final http = MediaHttpClient(scheduler: scheduler);
      final live = LiveRepository(db, DocumentClient(http));
      final probe = LiveProbe(
        http,
        LiveHealthRepository(db),
        networkTimeout: const Duration(seconds: 8),
      );
      try {
        if (const bool.fromEnvironment('FETCH_PLAYLISTS')) await _fetch(live);
        final channels = (await live.channels())
            .expand((c) => c.entries)
            .where((c) => !c.health.removed)
            .toList();
        // ignore: avoid_print
        print('CATALOG ${channels.length} channel sources');
        if (const bool.fromEnvironment('CATALOG_ONLY')) return;
        final report = File(
          const String.fromEnvironment(
            'LIVE_AUDIT_REPORT',
            defaultValue: 'artifacts/live-audit-20261028.jsonl',
          ),
        );
        final completed = <String>{};
        if (await report.exists()) {
          for (final line in await report.readAsLines()) {
            final row = jsonDecode(line) as Map;
            completed.add('${row["id"]}|${row["signature"]}');
          }
        }
        final pending = channels
            .where((c) => !completed.contains('${c.id}|${c.urls.join('|')}'))
            .toList();
        var cursor = 0, count = 0;
        Future<void> worker() async {
          while (cursor < pending.length) {
            final c = pending[cursor++];
            final result = await probe.check(c, CancellationToken());
            final row = {
              'id': c.id,
              'name': c.name,
              'listId': c.listId,
              'listName': c.listName,
              'signature': c.urls.join('|'),
              'checkedAt': DateTime.now().millisecondsSinceEpoch,
              'availability': result.availability.name,
              'latencyMs': result.latencyMs,
              'message': result.message,
              'preferredUrl': result.preferredUrl,
              'resolution': result.resolution,
              'languages': result.languages,
            };
            // Synchronous append makes concurrent workers produce complete JSON lines.
            report.writeAsStringSync(
              '${jsonEncode(row)}\n',
              mode: FileMode.append,
            );
            count++;
            if (count % 25 == 0 || count == pending.length) {
              // ignore: avoid_print
              print('AUDITED $count/${pending.length}');
            }
          }
        }

        await Future.wait(List.generate(16, (_) => worker()));
        final results = [
          for (final line in await report.readAsLines())
            jsonDecode(line) as Map,
        ];
        // ignore: avoid_print
        print({
          for (final state in LiveAvailability.values)
            state.name: results
                .where((r) => r['availability'] == state.name)
                .length,
        });
      } finally {
        await probe.close();
        http.close();
        scheduler.close();
        await db.close();
      }
    },
    timeout: const Timeout(Duration(hours: 2)),
  );
}

Future<void> _fetch(LiveRepository live) async {
  final catalog =
      jsonDecode(await File('assets/live_candidates.json').readAsString())
          as Map;
  final entries = (catalog['lists'] as List).cast<Map>();
  final existing = await live.lists();
  for (final row in existing) {
    if (!entries.any((e) => e['url'] == row['url'])) entries.add(row);
  }
  final results = <Map<String, Object?>>[];
  var cursor = 0;
  Future<void> worker() async {
    while (cursor < entries.length) {
      final e = entries[cursor++];
      final result = <String, Object?>{'name': e['name'], 'url': e['url']};
      try {
        await live.import(
          e['name'] as String,
          Uri.parse(e['url'] as String),
          headers: Map<String, String>.from(e['headers'] as Map? ?? {}),
        );
        result['status'] = 'available';
      } catch (error) {
        result['status'] = 'inconclusive';
        result['error'] = error.toString();
      }
      results.add(result);
      // ignore: avoid_print
      print('PLAYLIST ${e["name"]}: ${result["status"]}');
    }
  }

  await Future.wait(List.generate(3, (_) => worker()));
  await File(
    'artifacts/live-playlist-audit-20261028.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(results));
}
