import '../../sources/domain/video_source.dart';
import 'channel_identity.dart';
import 'channel_order.dart';
import 'live_channel.dart';
import 'live_health.dart';

/// Presentation groups retain original rows for probing and user preferences.
List<LiveChannel> mergeChannelAliases(List<LiveChannel> channels) {
  final groups = <String, List<LiveChannel>>{};
  for (final channel in channels) {
    final state = channel.health.removed
        ? 'removed'
        : channel.health.enabled
        ? 'enabled'
        : 'disabled';
    final key = '${channelIdentity(channel.name)}|$state';
    groups.putIfAbsent(key, () => []).add(channel);
  }
  final result = [for (final group in groups.values) _merge(group)];
  result.sort(compareChannels);
  return result;
}

LiveChannel _merge(List<LiveChannel> members) {
  if (members.length == 1) return members.single;
  members.sort((a, b) {
    if (a.urls.isEmpty != b.urls.isEmpty) return a.urls.isEmpty ? 1 : -1;
    final aOk = a.health.availability == LiveAvailability.responding;
    final bOk = b.health.availability == LiveAvailability.responding;
    if (aOk != bOk) return aOk ? -1 : 1;
    return a.id.compareTo(b.id);
  });
  final first = members.first;
  final available = members.where((c) => c.urls.isNotEmpty).toList();
  final watched = members.map((c) => c.watchedAt).whereType<DateTime>().toList()
    ..sort();
  final health = available.map((c) => c.health).toList();
  final availability =
      health.any((h) => h.availability == LiveAvailability.responding)
      ? LiveAvailability.responding
      : health.isNotEmpty &&
            health.every((h) => h.availability == LiveAvailability.unavailable)
      ? LiveAvailability.unavailable
      : health.any((h) => h.availability == LiveAvailability.inconclusive)
      ? LiveAvailability.inconclusive
      : LiveAvailability.unknown;
  return LiveChannel(
    id: stableId(
      'programme|${channelIdentity(first.name)}|${first.health.enabled}|${first.health.removed}',
    ),
    listId: first.listId,
    name: channelDisplayName(first.name),
    group: first.group,
    logo:
        members
            .map((c) => c.logo)
            .where((logo) => logo.isNotEmpty)
            .firstOrNull ??
        '',
    tvgId: first.tvgId,
    headers: first.headers,
    metadata: first.metadata,
    urls: {for (final c in members) ...c.playbackUrls}.toList(),
    favorite: members.any((c) => c.favorite),
    recent: watched.isNotEmpty,
    watchedAt: watched.lastOrNull,
    listName: members
        .map((c) => c.listName)
        .where((name) => name.isNotEmpty)
        .toSet()
        .join(' / '),
    health: LiveHealth(
      enabled: first.health.enabled,
      removed: first.health.removed,
      availability: availability,
      latencyMs: first.health.latencyMs,
      checkedAt: first.health.checkedAt,
      message: first.health.message,
      preferredUrl: first.health.preferredUrl,
      resolution: first.health.resolution,
      languages: first.health.languages,
    ),
    members: List.unmodifiable(members),
  );
}
