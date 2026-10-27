import 'dart:convert';
import 'dart:io';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/live/data/live_playlist_parser.dart';

Future<void> main() async {
  final http = MediaHttpClient();
  try {
    final source = Uri.parse(
      'https://raw.githubusercontent.com/popocoding/awesome-m3u/refs/heads/main/radio/cn.m3u',
    );
    final document = await DocumentClient(
      http,
    ).get(source, maxBytes: 4 * 1024 * 1024);
    final stations = parseLivePlaylist(document.text, document.uri, 'radio');
    if (stations.isEmpty) throw StateError('Radio source is empty');
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'source': source.toString(),
        'stations': stations.length,
        'groups': stations.map((station) => station.group).toSet().toList(),
        'sample': stations.take(6).map((station) => station.name).toList(),
        'streamPlaybackVerified': false,
      }),
    );
  } finally {
    http.close();
  }
}
