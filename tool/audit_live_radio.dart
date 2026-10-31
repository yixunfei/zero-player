import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/application/live_probe.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/data/live_playlist_parser.dart';
import 'package:zero_player/features/live/data/playlist_epg.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';

/// Explicit public-network audit. Writes only build evidence, never the user's DB.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'sample current public live and radio media',
    () async {
      final http = MediaHttpClient();
      final db = AppDatabase.memory();
      final probe = LiveProbe(
        http,
        LiveHealthRepository(db),
        networkTimeout: const Duration(seconds: 5),
      );
      const extra = bool.fromEnvironment('EXTRA');
      final sources = extra
          ? [
              'https://raw.githubusercontent.com/iptv-org/iptv/master/streams/cn.m3u',
              'https://raw.githubusercontent.com/ssili126/tv/main/itvlist.m3u',
              'https://raw.githubusercontent.com/fanmingming/live/main/tv/m3u/itv.m3u',
            ]
          : [
              'https://raw.githubusercontent.com/popocoding/awesome-m3u/refs/heads/main/radio/cn.m3u',
              'https://raw.githubusercontent.com/fanmingming/live/main/tv/m3u/index.m3u',
              'https://m3u.ibert.me/cn.m3u',
            ];
      final reports = <Map<String, Object?>>[];
      try {
        for (final source in sources) {
          final report = <String, Object?>{'source': source};
          reports.add(report);
          try {
            final doc = await DocumentClient(http).get(
              Uri.parse(source),
              networkTimeout: const Duration(seconds: 15),
            );
            final channels = parseLivePlaylist(doc.text, doc.uri, source);
            report['count'] = channels.length;
            report['epg'] = playlistEpg(doc.text, doc.uri)?.toString();
            final sample = channels.take(24).toList();
            final results = <Map<String, Object?>>[];
            var cursor = 0;
            Future<void> worker() async {
              while (cursor < sample.length) {
                final LiveChannel channel = sample[cursor++];
                final result = await probe.check(channel, CancellationToken());
                results.add({
                  'name': channel.name,
                  'hosts': channel.urls.map((u) => u.host).toSet().toList(),
                  'status': result.availability.name,
                  'message': result.message,
                  'latencyMs': result.latencyMs,
                });
              }
            }

            final clock = Stopwatch()..start();
            await Future.wait(List.generate(8, (_) => worker()));
            report['elapsedMs'] = clock.elapsedMilliseconds;
            report['sample'] = results;
          } catch (error) {
            report['error'] = error.runtimeType.toString();
          }
        }
        await File(
          extra
              ? 'build/live-radio-extra-audit.json'
              : 'build/live-radio-public-audit.json',
        ).writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'time': DateTime.now().toUtc().toIso8601String(),
            'reports': reports,
          }),
        );
      } finally {
        await probe.close();
        http.close();
        await db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
