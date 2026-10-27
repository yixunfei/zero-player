import '../../sources/domain/video_source.dart';
import '../domain/live_channel.dart';
import 'm3u_parser.dart';

List<LiveChannel> parseLivePlaylist(String input, Uri base, String listId) {
  final text = input.replaceFirst(String.fromCharCode(0xfeff), '').trim();
  if (text.startsWith('#EXTM3U')) return parseM3u(text, base, listId);
  if (text.startsWith('<') || text.startsWith('{')) {
    throw const FormatException('返回的是网页或配置文件，不是直播频道列表');
  }
  final channels = <String, LiveChannel>{};
  var group = '';
  for (final raw in text.split(String.fromCharCode(10))) {
    final line = raw.trim();
    final comma = line.indexOf(',');
    if (comma <= 0) continue;
    final name = line.substring(0, comma).trim();
    final address = line.substring(comma + 1).trim();
    if (address == '#genre#') {
      group = name;
      continue;
    }
    final urls = <Uri>[];
    for (final entry in address.split('#')) {
      final uri = Uri.tryParse(entry.trim());
      if (uri != null &&
          {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        urls.add(uri);
      }
    }
    if (urls.isEmpty) continue;
    final id = stableId('$listId|$group|$name');
    channels[id] = LiveChannel(
      id: id,
      listId: listId,
      name: name,
      group: group,
      urls: {...?channels[id]?.urls, ...urls}.take(100).toList(),
    );
    if (channels.length > 10000) throw const FormatException('频道数量超过 10000');
  }
  if (channels.isEmpty) throw const FormatException('没有可导入的 HTTP(S) 直播频道');
  return channels.values.toList();
}
