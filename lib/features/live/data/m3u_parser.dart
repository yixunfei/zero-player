import '../../sources/domain/video_source.dart';
import '../../../core/text/display_text.dart';
import '../domain/live_channel.dart';

List<LiveChannel> parseM3u(String input, Uri base, String listId) {
  if (!input.trimLeft().startsWith('#EXTM3U') ||
      input.contains('#EXT-X-TARGETDURATION:') ||
      input.contains('#EXT-X-STREAM-INF:')) {
    throw const FormatException('请输入频道 M3U 列表，而非单个 HLS 视频');
  }
  final channels = <String, LiveChannel>{};
  var name = '';
  var group = '';
  var logo = '';
  var tvgId = '';
  var headers = <String, String>{};
  final attributes = RegExp(r'([\w-]+)="([^"]*)"');
  for (final raw in input.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.startsWith('#EXTINF:')) {
      final attrs = {for (final m in attributes.allMatches(line)) m[1]!: m[2]!};
      // The display-name comma must be outside quoted metadata.
      var quoted = false;
      var divider = -1;
      for (var i = 0; i < line.length; i++) {
        if (line[i] == '"') quoted = !quoted;
        if (line[i] == ',' && !quoted) {
          divider = i;
          break;
        }
      }
      name = divider < 0
          ? attrs['tvg-name'] ?? '未命名频道'
          : line.substring(divider + 1).trim();
      name = displayText(name);
      group = displayText(attrs['group-title'] ?? '');
      logo = attrs['tvg-logo'] ?? '';
      tvgId = attrs['tvg-id'] ?? '';
      headers = {};
    } else if (line.startsWith('#EXTGRP:')) {
      group = displayText(line.substring(8));
    } else if (line.startsWith('#EXTVLCOPT:http-user-agent=')) {
      headers['User-Agent'] = line.substring(
        '#EXTVLCOPT:http-user-agent='.length,
      );
    } else if (line.startsWith('#EXTVLCOPT:http-referrer=')) {
      headers['Referer'] = line.substring('#EXTVLCOPT:http-referrer='.length);
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      Uri uri;
      try {
        uri = base.resolve(line);
      } on FormatException {
        continue;
      }
      if (!{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        continue;
      }
      final id = stableId(
        '$listId|${tvgId.isNotEmpty ? tvgId : '$group|$name'}',
      );
      final old = channels[id];
      channels[id] = LiveChannel(
        id: id,
        listId: listId,
        name: name.isEmpty ? uri.host : name,
        group: group,
        logo: _logoUrl(logo, base),
        tvgId: tvgId,
        urls: {...?old?.urls, uri}.take(100).toList(),
        headers: Map.unmodifiable({...?old?.headers, ...headers}),
      );
      if (channels.length > 10000) throw const FormatException('频道数量超过 10000');
    }
  }
  return channels.values.toList();
}

String _logoUrl(String value, Uri base) {
  if (value.isEmpty) return '';
  try {
    final uri = base.resolve(value);
    return {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty
        ? uri.toString()
        : '';
  } on FormatException {
    return '';
  }
}

String exportM3u(List<LiveChannel> channels) {
  String clean(String value) => value.replaceAll(RegExp(r'[\r\n"]'), ' ');
  final output = StringBuffer('#EXTM3U\n');
  for (final channel in channels) {
    for (final uri in channel.urls) {
      output.writeln(
        '#EXTINF:-1 tvg-id="${clean(channel.tvgId)}" '
        'tvg-logo="${clean(channel.logo)}" group-title="${clean(channel.group)}",${clean(channel.name)}',
      );
      for (final header in channel.headers.entries) {
        final option = switch (header.key.toLowerCase()) {
          'user-agent' => 'http-user-agent',
          'referer' => 'http-referrer',
          _ => null,
        };
        if (option != null) {
          output.writeln('#EXTVLCOPT:$option=${clean(header.value)}');
        }
      }
      output.writeln(uri);
    }
  }
  return output.toString();
}
