import 'hls_manifest.dart';

final class HlsQuality {
  const HlsQuality(this.uri, this.label, this.bandwidth);
  final Uri uri;
  final String label;
  final int bandwidth;
}

List<HlsQuality> hlsQualities(HlsManifest manifest) {
  final result = <HlsQuality>[];
  String? attributes;
  for (final raw in manifest.lines) {
    final line = raw.trim();
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      attributes = line;
    } else if (attributes != null && line.isNotEmpty && !line.startsWith('#')) {
      final uri = manifest.baseUri.resolve(line);
      final resolution = RegExp(
        r'RESOLUTION=(\d+x\d+)',
      ).firstMatch(attributes)?.group(1);
      final bandwidth =
          int.tryParse(
            RegExp(
                  r'(?:[:,])BANDWIDTH=(\d+)',
                ).firstMatch(attributes)?.group(1) ??
                '',
          ) ??
          0;
      if ({'http', 'https'}.contains(uri.scheme) && uri.userInfo.isEmpty) {
        result.add(
          HlsQuality(
            uri,
            '${resolution ?? '原始分辨率'}${bandwidth > 0 ? ' · ${(bandwidth / 1000000).toStringAsFixed(1)} Mbps' : ''}',
            bandwidth,
          ),
        );
      }
      attributes = null;
    }
  }
  return result;
}

/// Keep audio/subtitle rendition groups and keys intact when narrowing the
/// master. Opening a video-only variant directly can otherwise lose audio.
HlsManifest selectHlsQuality(HlsManifest manifest, Uri? selected) {
  if (!manifest.isMaster ||
      selected == null ||
      !hlsQualities(manifest).any((v) => v.uri == selected)) {
    return manifest;
  }
  final output = <String>[];
  String? pending;
  for (final raw in manifest.lines) {
    final line = raw.trim();
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      pending = raw;
    } else if (pending != null && line.isNotEmpty && !line.startsWith('#')) {
      if (manifest.baseUri.resolve(line) == selected) {
        output.add(pending);
        output.add(raw);
      }
      pending = null;
    } else {
      output.add(raw);
    }
  }
  return HlsManifest.parse(
    output.join('\n'),
    manifest.baseUri,
    variables: manifest.variables,
  );
}
