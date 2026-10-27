import 'live_health.dart';

final class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.listId,
    required this.name,
    required this.urls,
    this.group = '',
    this.logo = '',
    this.tvgId = '',
    this.headers = const {},
    this.favorite = false,
    this.recent = false,
    this.health = const LiveHealth(),
    this.listName = '',
    this.watchedAt,
  });
  final String id;
  final String listId;
  final String name;
  final List<Uri> urls;
  final String group;
  final String logo;
  final String tvgId;
  final Map<String, String> headers;
  final bool favorite;
  final bool recent;
  final LiveHealth health;
  final String listName;
  final DateTime? watchedAt;

  /// A successful probe only reorders this channel's own alternatives.
  List<Uri> get playbackUrls {
    final preferred = health.preferredUrl;
    return [
      ...urls.where((u) => u.toString() == preferred),
      ...urls.where((u) => u.toString() != preferred),
    ];
  }
}

final class EpgProgram {
  const EpgProgram(this.channelId, this.title, this.start, this.end);
  final String channelId;
  final String title;
  final DateTime start;
  final DateTime end;
}
