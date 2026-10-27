/// A lossless line model: unknown tags and discontinuities survive rewriting.
/// URI attributes are handled separately from full-line playlist references.
final class HlsManifest {
  HlsManifest._(this.baseUri, this.lines, this.segments, this.isMaster);

  final Uri baseUri;
  final List<String> lines;
  final List<HlsSegment> segments;
  final bool isMaster;
  bool get isComplete => lines.contains('#EXT-X-ENDLIST');
  Duration get duration =>
      segments.fold(Duration.zero, (sum, s) => sum + s.duration);

  Set<Uri> get playlistUris {
    final result = <Uri>{};
    var variant = false;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        variant = true;
      } else if (variant && line.isNotEmpty && !line.startsWith('#')) {
        result.add(_resolve(baseUri, line));
        variant = false;
      } else if (line.startsWith('#EXT-X-MEDIA:') ||
          line.startsWith('#EXT-X-I-FRAME-STREAM-INF:') ||
          line.startsWith('#EXT-X-RENDITION-REPORT:')) {
        for (final match in _uriAttribute.allMatches(line)) {
          result.add(_resolve(baseUri, match.group(2)!));
        }
      }
    }
    return result;
  }

  static const _uriTags = {
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
  static final _uriAttribute = RegExp(r'([:,])URI="([^"]*)"');

  factory HlsManifest.parse(String text, Uri baseUri) {
    final lines = text.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'));
    if (lines.isEmpty || lines.first.trim() != '#EXTM3U') {
      throw const FormatException('Not an HLS manifest');
    }
    final segments = <HlsSegment>[];
    var duration = Duration.zero;
    var position = Duration.zero;
    var sequence = 0;
    String? range;
    var discontinuity = false;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.parse(line.split(':').last);
      } else if (line.startsWith('#EXTINF:')) {
        final value = double.parse(line.substring(8).split(',').first);
        if (!value.isFinite || value < 0) {
          throw const FormatException('Invalid EXTINF');
        }
        duration = Duration(microseconds: (value * 1000000).round());
      } else if (line.startsWith('#EXT-X-BYTERANGE:')) {
        range = line.substring(17);
      } else if (line == '#EXT-X-DISCONTINUITY') {
        discontinuity = true;
      } else if (line.isNotEmpty &&
          !line.startsWith('#') &&
          duration > Duration.zero) {
        segments.add(
          HlsSegment(
            uri: _resolve(baseUri, line),
            sequence: sequence++,
            start: position,
            duration: duration,
            byteRange: range,
            discontinuity: discontinuity,
          ),
        );
        position += duration;
        duration = Duration.zero;
        range = null;
        discontinuity = false;
      }
    }
    return HlsManifest._(
      baseUri,
      List.unmodifiable(lines),
      List.unmodifiable(segments),
      lines.any((line) => line.startsWith('#EXT-X-STREAM-INF:')),
    );
  }

  String rewrite(Uri Function(Uri uri) map) => lines
      .map((raw) {
        final line = raw.trim();
        if (line.isEmpty) return raw;
        if (!line.startsWith('#')) {
          return map(_resolve(baseUri, line)).toString();
        }
        final tag = line.split(':').first;
        if (!_uriTags.contains(tag)) return raw;
        return raw.replaceAllMapped(_uriAttribute, (match) {
          final uri = _resolve(baseUri, match.group(2)!);
          return '${match.group(1)}URI="${map(uri)}"';
        });
      })
      .join('\n');

  static Uri _resolve(Uri base, String reference) {
    final uri = base.resolve(reference);
    if (!{'http', 'https'}.contains(uri.scheme) || uri.userInfo.isNotEmpty) {
      throw const FormatException('Unsupported HLS resource URI');
    }
    return uri;
  }
}

final class HlsSegment {
  const HlsSegment({
    required this.uri,
    required this.sequence,
    required this.start,
    required this.duration,
    required this.byteRange,
    required this.discontinuity,
  });
  final Uri uri;
  final int sequence;
  final Duration start;
  final Duration duration;
  final String? byteRange;
  final bool discontinuity;
}
