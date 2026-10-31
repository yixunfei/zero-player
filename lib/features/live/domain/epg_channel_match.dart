import 'channel_identity.dart';

/// Prefer explicit IDs. Missing IDs may use one unambiguous existing name alias.
String? matchEpgChannel(String tvgId, String name, Iterable<String> ids) {
  final candidates = ids.toSet();
  if (tvgId.isNotEmpty) {
    if (candidates.contains(tvgId)) return tvgId;
    final matches = candidates
        .where((id) => id.toLowerCase() == tvgId.toLowerCase())
        .toList();
    return matches.length == 1 ? matches.single : null;
  }
  final matches = candidates
      .where((id) => channelIdentity(id) == channelIdentity(name))
      .toList();
  return matches.length == 1 ? matches.single : null;
}
