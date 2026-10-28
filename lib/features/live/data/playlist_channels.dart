import 'dart:convert';
import '../../sources/domain/video_source.dart';
import '../domain/channel_identity.dart';
import '../domain/live_channel.dart';
import 'channel_urls.dart';

String channelHeaderKey(Map<String, String> headers) => jsonEncode({
  for (final key in headers.keys.toList()..sort())
    key.toLowerCase(): headers[key],
});

/// Preserve stored preferences when a publisher changes CCTV display names.
List<LiveChannel> preparePlaylistChannels(
  List<LiveChannel> channels,
  List<Map<String, Object?>> previous,
  Map<String, String> listHeaders,
) {
  final old = <String, String>{};
  for (final row in previous) {
    final headers = Map<String, String>.from(
      jsonDecode(row['headers'] as String),
    );
    old.putIfAbsent(
      '${channelIdentity(row['name'] as String)}|${channelHeaderKey(headers)}',
      () => row['id'] as String,
    );
  }
  final result = <String, LiveChannel>{};
  for (final channel in channels) {
    final headers = {...listHeaders, ...channel.headers};
    final key = '${channelIdentity(channel.name)}|${channelHeaderKey(headers)}';
    final first = result[key];
    final id =
        first?.id ??
        old[key] ??
        (cctvIdentity(channel.name) == null
            ? channel.id
            : stableId('${channel.listId}|$key'));
    result[key] = LiveChannel(
      id: id,
      listId: channel.listId,
      name: channelDisplayName(channel.name),
      group: first?.group ?? channel.group,
      logo: first?.logo.isNotEmpty == true ? first!.logo : channel.logo,
      tvgId: first?.tvgId.isNotEmpty == true ? first!.tvgId : channel.tvgId,
      urls: appendChannelUrls(first?.urls ?? [], channel.urls),
      headers: headers,
    );
  }
  return result.values.toList();
}
