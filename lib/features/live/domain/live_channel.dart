import 'live_health.dart';
import 'live_metadata.dart';
import '../../../core/network/header_policy.dart';

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
    this.headerOrigin,
    this.favorite = false,
    this.recent = false,
    this.health = const LiveHealth(),
    this.listName = '',
    this.watchedAt,
    this.members = const [],
    this.metadata = const LiveMetadata(),
  });
  final String id;
  final String listId;
  final String name;
  final List<Uri> urls;
  final String group;
  final String logo;
  final String tvgId;
  final Map<String, String> headers;
  final Uri? headerOrigin;
  final bool favorite;
  final bool recent;
  final LiveHealth health;
  final String listName;
  final DateTime? watchedAt;
  final List<LiveChannel> members;
  final LiveMetadata metadata;
  List<String> get categories => {
    for (final entry in entries) ...entry.metadata.categories,
    for (final entry in entries)
      if (entry.group.isNotEmpty) entry.group,
  }.toList();
  List<String> get languages => {
    for (final entry in entries) ...entry.metadata.languages,
    for (final entry in entries) ...entry.health.languages,
  }.toList();
  List<String> get resolutions => {
    for (final entry in entries)
      if (entry.health.resolution?.isNotEmpty == true)
        entry.health.resolution!
      else if (entry.metadata.resolution.isNotEmpty)
        entry.metadata.resolution,
  }.toList();
  List<LiveChannel> get entries => members.isEmpty ? [this] : members;
  List<String> get preferenceIds => entries.map((c) => c.id).toList();

  Map<String, String> headersFor(Uri uri) {
    final entry = entries.where((c) => c.urls.contains(uri)).firstOrNull;
    if (entry == null) return const {};
    return HeaderPolicy.playlistHeaders(entry.headerOrigin, uri, entry.headers);
  }

  LiveChannel withFavorite(bool value) => LiveChannel(
    id: id,
    listId: listId,
    name: name,
    urls: urls,
    group: group,
    logo: logo,
    tvgId: tvgId,
    headers: headers,
    headerOrigin: headerOrigin,
    favorite: value,
    recent: recent,
    health: health,
    listName: listName,
    watchedAt: watchedAt,
    members: members,
    metadata: metadata,
  );

  LiveChannel withHealth(LiveHealth value) => LiveChannel(
    id: id,
    listId: listId,
    name: name,
    urls: urls,
    group: group,
    logo: logo,
    tvgId: tvgId,
    headers: headers,
    headerOrigin: headerOrigin,
    favorite: favorite,
    recent: recent,
    health: value,
    listName: listName,
    watchedAt: watchedAt,
    members: members,
    metadata: metadata,
  );

  /// A successful probe only reorders this channel's own alternatives.
  List<Uri> get playbackUrls {
    final preferred = health.preferredUrl;
    final eligible =
        health.verifiedOnly &&
            health.availability == LiveAvailability.responding
        ? urls.where(
            (uri) =>
                health.verifiedUrls.contains('$uri') || '$uri' == preferred,
          )
        : urls;
    return [
      ...eligible.where((u) => u.toString() == preferred),
      ...eligible.where((u) => u.toString() != preferred),
    ];
  }
}

final class EpgProgram {
  const EpgProgram(
    this.channelId,
    this.title,
    this.start,
    this.end, {
    this.matchedByName = false,
    this.sourceUrl = '',
  });
  final String channelId;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool matchedByName;
  final String sourceUrl;
  Duration get duration => end.difference(start);
}
