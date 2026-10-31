import '../../core/network/network_target_policy.dart';

/// Validate before any consumer schedules downloads or exposes a native input.
void validateHlsResources(List<String> lines, Uri base) {
  const resourceTags = {
    '#EXT-X-KEY',
    '#EXT-X-MAP',
    '#EXT-X-MEDIA',
    '#EXT-X-I-FRAME-STREAM-INF',
    '#EXT-X-SESSION-KEY',
    '#EXT-X-SESSION-DATA',
    '#EXT-X-PART',
    '#EXT-X-PRELOAD-HINT',
    '#EXT-X-RENDITION-REPORT',
  };
  final anyUri = RegExp(r'[:,]\s*(?:[A-Z-]+-)?URI\s*=', caseSensitive: false);
  final uriAttribute = RegExp(r'([:,]\s*)URI="([^"]*)"');
  for (final raw in lines) {
    if (RegExp(r'[\x00-\x08\x0a-\x1f\x7f]').hasMatch(raw)) {
      throw const FormatException('HLS 清单包含控制字符');
    }
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (!line.startsWith('#')) {
      NetworkTargetPolicy.validateUri(base.resolve(line));
      continue;
    }
    final tag = line.split(':').first;
    final count = anyUri.allMatches(line).length;
    if (!resourceTags.contains(tag)) {
      if (tag.startsWith('#EXT') && count > 0) {
        throw const FormatException('Unsupported HLS resource attribute');
      }
      continue;
    }
    final matches = uriAttribute.allMatches(line).toList();
    if (count != matches.length || matches.length > 1) {
      throw const FormatException(
        'Malformed or duplicate HLS resource attribute',
      );
    }
    for (final match in matches) {
      final uri = base.resolve(match[2]!);
      final key = tag == '#EXT-X-KEY' || tag == '#EXT-X-SESSION-KEY';
      if (key && {'data', 'skd'}.contains(uri.scheme)) continue;
      NetworkTargetPolicy.validateUri(uri);
    }
  }
}
