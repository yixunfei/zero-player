import 'dart:convert';
import 'dart:io';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/poster_repository.dart';

/// Opt-in public network smoke test; never part of the deterministic test suite.
Future<void> main() async {
  final http = MediaHttpClient();
  final network = DocumentClient(http);
  final posters = PosterRepository(network);
  final results = <Map<String, Object?>>[];
  try {
    final uri = Uri.https('movie.douban.com', '/j/search_subjects', {
      'type': 'movie',
      'tag': '热门',
      'page_limit': '8',
      'page_start': '0',
    });
    final data = (await network.get(uri)).json as Map;
    for (final item in (data['subjects'] as List).take(8)) {
      final url = '${item['cover']}';
      final result = <String, Object?>{'title': item['title'], 'url': url};
      try {
        final old = await network.get(
          Uri.parse(url),
          headers: {'User-Agent': 'Dart/3.12 (dart:io)'},
        );
        result['previous'] = isPosterPayload(old.bytes)
            ? 'image'
            : 'non-image body';
      } catch (error) {
        result['previous'] = '$error';
      }
      final lease = posters.acquire(url);
      try {
        final bytes = await lease.bytes;
        result['updated'] = 'image';
        result['bytes'] = bytes.length;
      } catch (error) {
        result['updated'] = '$error';
      } finally {
        lease.release();
      }
      results.add(result);
      stdout.writeln(jsonEncode(result));
    }
    final report = {
      'checkedAt': DateTime.now().toIso8601String(),
      'provider': 'douban',
      'succeeded': results.where((r) => r['updated'] == 'image').length,
      'total': results.length,
      'results': results,
    };
    await File(
      'artifacts/home-public-cover-probe.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  } finally {
    posters.close();
    http.close();
  }
}
