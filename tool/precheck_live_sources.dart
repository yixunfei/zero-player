import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/live/data/live_playlist_parser.dart';
import 'package:zero_player/features/live/domain/channel_order.dart';

/// Explicit developer-time retrieval check. This never starts media playback.
void main() {
  test(
    'precheck built-in playlist retrieval and parsing',
    () async {
      final input =
          jsonDecode(await File('assets/live_candidates.json').readAsString())
              as Map;
      final entries = (input['lists'] as List).cast<Map>();
      final http = MediaHttpClient();
      final network = DocumentClient(http);
      final results = <Map<String, Object?>>[];
      var cursor = 0;
      Future<void> worker() async {
        while (cursor < entries.length) {
          final entry = entries[cursor++];
          final result = <String, Object?>{
            'name': entry['name'],
            'url': entry['url'],
            'origin': entry['origin'],
          };
          final clock = Stopwatch()..start();
          try {
            final doc = await network.get(
              Uri.parse(entry['url'] as String),
              headers: Map<String, String>.from(entry['headers'] as Map? ?? {}),
              maxBytes: 8 * 1024 * 1024,
            );
            final channels = parseLivePlaylist(doc.text, doc.uri, 'audit');
            if (channels.isEmpty) throw const FormatException('没有可解析的频道');
            result.addAll({
              'status': 'available',
              'defaultEnabled': true,
              'channels': channels.length,
              'cctv': channels.where((c) => channelGroup(c) == '央视').length,
            });
          } catch (error) {
            final certain =
                error is FormatException ||
                error is RemoteFailure &&
                    (error.kind == FailureKind.invalid ||
                        error.kind == FailureKind.unsupported ||
                        error.kind == FailureKind.http &&
                            {
                              400,
                              401,
                              403,
                              404,
                              405,
                              410,
                              451,
                            }.contains(error.status));
            result.addAll({
              'status': certain ? 'unavailable' : 'inconclusive',
              'defaultEnabled': !certain,
              'reason': error.toString(),
            });
          }
          result['elapsedMs'] = clock.elapsedMilliseconds;
          results.add(result);
        }
      }

      try {
        await Future.wait(List.generate(3, (_) => worker()));
      } finally {
        http.close();
      }
      final report = {
        'checkedAt': DateTime.now().toUtc().toIso8601String(),
        'scope':
            'Playlist retrieval/parsing only; media availability depends on the user network.',
        'results': results,
      };
      final text = const JsonEncoder.withIndent('  ').convert(report);
      await File('assets/live_precheck.json').writeAsString(text);
      await File(
        'artifacts/interaction-live-precheck.json',
      ).writeAsString(text);
      // ignore: avoid_print
      print({
        for (final state in ['available', 'unavailable', 'inconclusive'])
          state: results.where((r) => r['status'] == state).length,
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
