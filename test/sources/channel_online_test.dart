import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/catalog/data/provider_factory.dart';
import 'package:zero_player/features/live/data/live_playlist_parser.dart';
import 'package:zero_player/features/live/data/tonkiang_service.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';

void initializeOnlineTest() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
}

void main() {
  initializeOnlineTest();
  test(
    'public channel integration sample',
    () async {
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final network = DocumentClient(http);
      final results = <Map<String, Object?>>[];
      try {
        for (final site in [
          ('kanju', 'https://kanju3.com/'),
          ('macCmsHtml', 'https://wu5mv.com/'),
        ]) {
          final provider = createVodProvider(
            VideoSource(
              id: site.$1,
              name: site.$1,
              kind: site.$1,
              endpoint: Uri.parse(site.$2),
            ),
            network,
          );
          try {
            final listing = await provider.search('三体');
            expect(listing.items, isNotEmpty);
            final item = await provider.detail(listing.items.first.id);
            expect(item.lines, isNotEmpty);
            final media = await provider.resolve(
              item.lines.first.episodes.first,
            );
            final row = <String, Object?>{
              'site': site.$1,
              'search': listing.items.length,
              'title': item.title,
              'lines': item.lines.length,
              'episodes': item.lines.first.episodes.length,
              'mediaHost': media.uri.host,
            };
            try {
              final doc = await network.get(
                media.uri,
                headers: media.headers,
                maxBytes: 512 * 1024,
                networkTimeout: const Duration(seconds: 10),
              );
              row['manifest'] = doc.text.trimLeft().startsWith('#EXTM3U');
            } catch (e) {
              row['mediaError'] = '$e';
            }
            results.add(row);
          } catch (e) {
            results.add({'site': site.$1, 'error': '$e'});
          }
        }
        final asset =
            jsonDecode(
                  await rootBundle.loadString('assets/live_candidates.json'),
                )
                as Map;
        for (final row in (asset['lists'] as List).cast<Map>()) {
          try {
            final url = Uri.parse(row['url'] as String);
            final doc = await network.get(
              url,
              maxBytes: 8 * 1024 * 1024,
              headers: Map<String, String>.from(row['headers'] as Map? ?? {}),
              networkTimeout: const Duration(seconds: 12),
            );
            final channels = parseLivePlaylist(doc.text, doc.uri, 'sample');
            results.add({'list': row['name'], 'channels': channels.length});
          } catch (e) {
            results.add({'list': row['name'], 'error': '$e'});
          }
        }
        try {
          final page = await TonkiangService(network).search('CCTV1');
          results.add({'site': 'tonkiang', 'channels': page.channels.length});
        } catch (e) {
          results.add({'site': 'tonkiang', 'error': '$e'});
        }
      } finally {
        http.close();
        final report = const JsonEncoder.withIndent('  ').convert(results);
        await File(
          'docs/implementation/CHANNEL-ONLINE-2026-10-27.json',
        ).writeAsString(report);
        // ignore: avoid_print
        print(report);
      }
      expect(
        results
            .where((r) => r['site'] == 'kanju' || r['site'] == 'macCmsHtml')
            .every((r) => !r.containsKey('error')),
        isTrue,
      );
    },
    skip: !const bool.fromEnvironment('CHANNEL_ONLINE'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
