import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/data/playlist_epg.dart';
import 'package:zero_player/features/live/domain/epg_channel_match.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('review declared XMLTV guides', () async {
    final catalog = AppDatabase(File('artifacts/live-audit-20261028.sqlite'));
    final epgDb = AppDatabase(
      File('artifacts/live-epg-review-20261028.sqlite'),
    );
    final http = MediaHttpClient();
    final live = LiveRepository(epgDb, DocumentClient(http));
    try {
      final lists = await catalog.rows(
        'SELECT id,name,url,snapshot FROM live_lists WHERE snapshot IS NOT NULL',
      );
      final guides = <Uri, List<Map<String, Object?>>>{};
      for (final row in lists) {
        final guide = playlistEpg(
          row['snapshot'] as String,
          Uri.parse(row['url'] as String),
        );
        if (guide != null) guides.putIfAbsent(guide, () => []).add(row);
      }
      final report = <Map<String, Object?>>[];
      const useCache = bool.fromEnvironment('EPG_USE_CACHE');
      final previous = useCache
          ? (jsonDecode(
                      await File(
                        'artifacts/live-epg-review-20261028.json',
                      ).readAsString(),
                    )
                    as List)
                .cast<Map>()
          : <Map>[];
      for (final entry in guides.entries) {
        final cached = previous
            .where((r) => r['url'] == entry.key.toString())
            .firstOrNull;
        if (useCache && cached?['status'] != 'available') {
          if (cached != null) report.add(Map<String, Object?>.from(cached));
          continue;
        }
        final result = <String, Object?>{
          'url': entry.key.toString(),
          'lists': entry.value.map((r) => r['name']).toList(),
        };
        try {
          if (!useCache) await live.refreshEpg(entry.key);
          final programmes = await epgDb.rows(
            'SELECT DISTINCT channel_id FROM epg_programs WHERE source=?',
            [entry.key.toString()],
          );
          final ids = programmes.map((p) => p['channel_id']).toSet();
          var matches = 0;
          for (final list in entry.value) {
            final channels = await catalog.rows(
              'SELECT name,tvg_id FROM live_channels WHERE list_id=?',
              [list['id']],
            );
            matches += channels
                .where(
                  (c) =>
                      matchEpgChannel(
                        c['tvg_id'] as String,
                        c['name'] as String,
                        ids.cast<String>(),
                      ) !=
                      null,
                )
                .length;
          }
          result.addAll({
            'status': ids.isEmpty ? 'noCurrentPrograms' : 'available',
            'guideChannels': ids.length,
            'matchedChannelSources': matches,
          });
        } catch (error) {
          result.addAll({'status': 'inconclusive', 'error': error.toString()});
        }
        report.add(result);
        // ignore: avoid_print
        print(result);
      }
      await File(
        'artifacts/live-epg-review-20261028.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    } finally {
      http.close();
      await catalog.close();
      await epgDb.close();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
