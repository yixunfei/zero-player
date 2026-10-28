import 'hls_manifest.dart';
import 'timeline.dart';

final class FilteredManifest {
  const FilteredManifest(this.manifest, this.timeline);
  final HlsManifest manifest;
  final MediaTimeline timeline;
}

/// Conservative opt-in: only explicit, paired CUE-OUT/CUE-IN blocks in static,
/// unencrypted TS playlists. Discontinuities alone are never ad evidence.
FilteredManifest filterDeclaredAds(HlsManifest input) {
  const unchanged = MediaTimeline([]);
  if (input.isMaster ||
      !input.isComplete ||
      input.lines.any(
        (l) =>
            l.startsWith('#EXT-X-KEY:') ||
            l.startsWith('#EXT-X-MAP:') ||
            l.startsWith('#EXT-X-BYTERANGE:'),
      )) {
    return FilteredManifest(input, unchanged);
  }
  final output = <String>[];
  final removed = <RemovedInterval>[];
  var inAd = false;
  var start = Duration.zero;
  var position = Duration.zero;
  var pending = Duration.zero;
  for (final line in input.lines) {
    if (line.startsWith('#EXT-X-CUE-OUT:') || line == '#EXT-X-CUE-OUT') {
      if (inAd) return FilteredManifest(input, unchanged);
      inAd = true;
      start = position;
      continue;
    }
    if (line == '#EXT-X-CUE-IN') {
      if (!inAd) return FilteredManifest(input, unchanged);
      if (position > start) removed.add(RemovedInterval(start, position));
      inAd = false;
      output.add('#EXT-X-DISCONTINUITY');
      continue;
    }
    if (line.startsWith('#EXTINF:')) {
      pending = Duration(
        microseconds:
            ((double.tryParse(line.substring(8).split(',').first) ?? 0) *
                    1000000)
                .round(),
      );
    }
    if (line.isNotEmpty && !line.startsWith('#')) position += pending;
    if (!inAd) output.add(line);
  }
  if (inAd ||
      removed.isEmpty ||
      removed.fold<Duration>(Duration.zero, (s, i) => s + i.end - i.start) >=
          position) {
    return FilteredManifest(input, unchanged);
  }
  return FilteredManifest(
    HlsManifest.parse(
      output.join('\n'),
      input.baseUri,
      variables: input.variables,
    ),
    MediaTimeline(removed),
  );
}
