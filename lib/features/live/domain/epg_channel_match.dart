import 'channel_identity.dart';

/// Prefer explicit IDs. Missing IDs may use one unambiguous existing name alias.
String? matchEpgChannel(String tvgId, String name, Iterable<String> ids) {
  final candidates = ids.toSet();
  if (tvgId.isNotEmpty) return candidates.contains(tvgId) ? tvgId : null;
  final matches = candidates
      .where((id) => channelIdentity(id) == channelIdentity(name))
      .toList();
  return matches.length == 1 ? matches.single : null;
}
