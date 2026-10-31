import 'dart:convert';
import '../../../core/network/header_policy.dart';

/// Read HTTP metadata only. Never forward native player options or scripts.
Map<String, String> playlistRequestHeaders(String line) {
  final lower = line.toLowerCase();
  if (lower.startsWith('#extvlcopt:')) {
    final equal = line.indexOf('=');
    if (equal < 0) return {};
    final key = switch (lower.substring(11, equal)) {
      'http-user-agent' => 'User-Agent',
      'http-referrer' || 'http-referer' => 'Referer',
      'http-origin' => 'Origin',
      _ => null,
    };
    return key == null
        ? {}
        : HeaderPolicy.sanitize({key: line.substring(equal + 1)});
  }
  if (lower.startsWith('#exthttp:')) {
    try {
      final data = jsonDecode(line.substring(9));
      if (data is! Map) return {};
      return HeaderPolicy.sanitize({
        for (final entry in data.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      });
    } on FormatException {
      return {};
    }
  }
  if (lower.startsWith('#kodiprop:inputstream.adaptive.common_headers=') ||
      lower.startsWith('#kodiprop:inputstream.adaptive.stream_headers=')) {
    return encodedRequestHeaders(line.substring(line.indexOf('=') + 1));
  }
  return {};
}

Map<String, String> encodedRequestHeaders(String input) {
  try {
    return HeaderPolicy.sanitize(Uri.splitQueryString(input));
  } on FormatException {
    return {};
  }
}
