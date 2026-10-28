import 'source_identity.dart';
import 'video_source.dart';

/// Exact names only: do not infer shared identity from substrings or domains.
List<List<VideoSource>> duplicateSourceGroups(List<VideoSource> sources) {
  final parent = List.generate(sources.length, (i) => i);
  int root(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  final keys = <String, int>{};
  for (var i = 0; i < sources.length; i++) {
    final source = sources[i];
    final name = source.displayName
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    for (final key in [
      'url:${sourceEndpointIdentity(source.kind, source.endpoint)}',
      if (name.isNotEmpty) 'name:$name',
    ]) {
      final previous = keys[key];
      if (previous == null) {
        keys[key] = i;
      } else {
        parent[root(i)] = root(previous);
      }
    }
  }
  final groups = <int, List<VideoSource>>{};
  for (var i = 0; i < sources.length; i++) {
    groups.putIfAbsent(root(i), () => []).add(sources[i]);
  }
  return groups.values.where((g) => g.length > 1).toList();
}

int compareDuplicateSources(VideoSource a, VideoSource b) {
  var result = _quality(a).compareTo(_quality(b));
  if (result != 0) return result;
  if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
  if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
  if (a.endpoint.scheme != b.endpoint.scheme) {
    return a.endpoint.scheme == 'https' ? -1 : 1;
  }
  result = (a.latencyMs ?? 999999).compareTo(b.latencyMs ?? 999999);
  return result != 0 ? result : a.id.compareTo(b.id);
}

int _quality(VideoSource source) {
  final diagnostic = source.diagnostics;
  if (source.checkedAt != null &&
      (diagnostic == null || source.checkedAt!.isAfter(diagnostic.checkedAt))) {
    return source.apiOk
        ? 0
        : source.failures > 0
        ? 2
        : 1;
  }
  return switch (diagnostic?.state) {
    'available' => 0,
    'unavailable' => 2,
    'missingDomain' => 3,
    _ => source.apiOk ? 0 : 1,
  };
}
