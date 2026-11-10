import 'music_track.dart';

/// Preserve spelling and version suffixes when grouping search results.
(String, String)? musicIdentity(MusicTrack track) => track.artist.trim().isEmpty
    ? null
    : (track.title.trim(), track.artist.trim());

List<List<MusicTrack>> groupMusicTracks(
  Iterable<MusicTrack> tracks, {
  required bool enabled,
}) {
  final groups = <Object, List<MusicTrack>>{};
  for (final track in tracks) {
    final key = enabled ? musicIdentity(track) ?? track.key : track.key;
    groups.putIfAbsent(key, () => []).add(track);
  }
  return groups.values.toList();
}

bool matchesMusic(MusicTrack original, MusicTrack candidate) {
  String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return original.artist.trim().isNotEmpty &&
      normalize(original.title) == normalize(candidate.title) &&
      normalize(original.artist) == normalize(candidate.artist);
}

const musicSourceStrategies = {
  'balanced': '平衡速度与音质',
  'fastest': '延迟优先',
  'quality': '音质优先',
};
