import '../../live/data/live_playlist_parser.dart';
import '../../live/domain/channel_identity.dart';
import '../../live/domain/live_channel.dart';
import '../../live/data/playlist_channels.dart';
import '../../sources/domain/video_source.dart';
import '../domain/radio_subscription.dart';

final class RadioSnapshot {
  RadioSnapshot({
    required this.text,
    required this.base,
    required this.updatedAt,
  });
  final String text;
  final Uri base;
  final DateTime updatedAt;

  List<LiveChannel> stations(RadioSubscription subscription) {
    final parsed = parseLivePlaylist(text, base, 'radio:${subscription.id}');
    if (parsed.isEmpty) throw const FormatException('广播列表为空');
    return [
      for (final entry in preparePlaylistChannels(parsed, const [], const {}))
        LiveChannel(
          id: stableId(
            'radio|${subscription.id}|${channelIdentity(entry.name)}'
            '${entry.headers.isEmpty ? '' : '|${channelHeaderKey(entry.headers)}'}',
          ),
          listId: subscription.id,
          listName: subscription.name,
          name: entry.name,
          urls: entry.urls,
          group: entry.group,
          headers: entry.headers,
          headerOrigin: base,
          metadata: entry.metadata,
          logo: entry.logo,
          tvgId: entry.tvgId,
        ),
    ];
  }

  Map<String, Object?> toJson() => {
    'text': text,
    'base': '$base',
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory RadioSnapshot.fromJson(Map data) {
    if (data['text'] is! String ||
        data['base'] is! String ||
        data['updatedAt'] is! int ||
        (data['updatedAt'] as int) <= 0) {
      throw const FormatException('广播快照结构无效');
    }
    final base = Uri.parse(data['base'] as String);
    if (!{'http', 'https'}.contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty) {
      throw const FormatException('广播快照基址无效');
    }
    return RadioSnapshot(
      text: data['text'] as String,
      base: base,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
    );
  }
}
