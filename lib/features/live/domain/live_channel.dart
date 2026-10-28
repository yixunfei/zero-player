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
    this.members = const [],
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
  final List<LiveChannel> members;
  List<LiveChannel> get entries => members.isEmpty ? [this] : members;
  List<String> get preferenceIds => entries.map((c) => c.id).toList();

  Map<String, String> headersFor(Uri uri) =>
      entries.where((c) => c.urls.contains(uri)).firstOrNull?.headers ??
      headers;

  LiveChannel withFavorite(bool value) => LiveChannel(
    id: id,
    listId: listId,
    name: name,
    urls: urls,
    group: group,
    logo: logo,
    tvgId: tvgId,
    headers: headers,
    favorite: value,
    recent: recent,
    health: health,
    listName: listName,
    watchedAt: watchedAt,
    members: members,
  );

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
