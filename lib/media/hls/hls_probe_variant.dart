import 'hls_manifest.dart';

/// Metadata belongs to the selected video variant, never an unrelated rendition.
({Uri uri, String? resolution, List<String> languages}) probeVariant(
  HlsManifest manifest,
) {
  Map<String, String>? variant;
  for (final raw in manifest.lines) {
    final line = raw.trim();
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      variant = _attributes(line);
    } else if (variant != null && line.isNotEmpty && !line.startsWith('#')) {
      final audio = variant['AUDIO'];
      final languages = <String>{};
      for (final rendition in manifest.lines) {
        if (!rendition.startsWith('#EXT-X-MEDIA:')) continue;
        final attrs = _attributes(rendition);
        if (audio != null &&
            attrs['GROUP-ID'] == audio &&
            attrs['TYPE'] == 'AUDIO' &&
            attrs['LANGUAGE']?.isNotEmpty == true) {
          languages.add(attrs['LANGUAGE']!);
        }
      }
      final resolution = variant['RESOLUTION'];
      return (
        uri: manifest.baseUri.resolve(line),
        resolution:
            resolution != null && RegExp(r'^\d+x\d+$').hasMatch(resolution)
            ? resolution
            : null,
        languages: languages.toList(),
      );
    }
  }
  throw const FormatException('没有播放变体');
}

Map<String, String> _attributes(String line) => {
  for (final match in RegExp(
    r'([A-Z-]+)=(?:"([^"]*)"|([^,]*))',
  ).allMatches(line))
    match[1]!: match[2] ?? match[3]!,
};
