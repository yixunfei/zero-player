import 'dart:convert';
import 'dart:io';
import 'package:zero_player/features/live/data/live_playlist_parser.dart';
import 'package:zero_player/features/radio/domain/radio_subscription.dart';

/// dart run tool/sync_radio_snapshot.dart; failed fetch/parse keeps the old file.
Future<void> main() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final uri = Uri.parse(builtinRadioUrl);
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes.addAll(chunk);
      if (bytes.length > 4 * 1024 * 1024) {
        throw const FormatException('广播列表超过上限');
      }
    }
    final text = utf8.decode(bytes);
    final stations = parseLivePlaylist(text, uri, 'radio');
    if (stations.isEmpty) throw const FormatException('广播列表为空');
    final output = File('assets/catalogs/radio/cn.snapshot.json');
    await output.parent.create(recursive: true);
    final temporary = File('${output.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'source': builtinRadioUrl,
        'repository': 'https://github.com/popocoding/awesome-m3u',
        'base': '$uri',
        'text': text,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }),
      flush: true,
    );
    await temporary.rename(output.path);
    stdout.writeln(
      'Saved ${stations.length} parsed radio stations to ${output.path}',
    );
  } finally {
    client.close(force: true);
  }
}
