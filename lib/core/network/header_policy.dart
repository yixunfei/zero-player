/// Credentials and custom headers are scoped to the exact original origin.
/// A redirect or HLS child on another origin must supply its own explicit scope.
final class HeaderPolicy {
  HeaderPolicy(Map<Uri, Map<String, String>> origins)
    : _origins = {
        for (final entry in origins.entries)
          origin(entry.key): Map<String, String>.unmodifiable(
            sanitize(entry.value),
          ),
      };

  final Map<String, Map<String, String>> _origins;

  static Map<String, String> sanitize(Map<String, String> headers) {
    const reserved = {
      'host',
      'connection',
      'content-length',
      'transfer-encoding',
      'upgrade',
      'proxy-authorization',
      'proxy-connection',
      'te',
      'trailer',
    };
    return {
      for (final entry in headers.entries)
        if (!reserved.contains(entry.key.toLowerCase()) &&
            RegExp(r'^[A-Za-z0-9!#$%&*+.^_|~-]+$').hasMatch(entry.key) &&
            !RegExp(r'[\x00-\x1f\x7f]').hasMatch(entry.value))
          entry.key: entry.value,
    };
  }

  static String origin(Uri uri) {
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    return '${uri.scheme}://$host:${uri.port}';
  }

  Map<String, String> forUri(Uri uri) => _origins[origin(uri)] ?? const {};

  bool containsOrigin(Uri uri) => _origins.containsKey(origin(uri));

  /// Resolved media hosts must not receive source account paths or URL tokens.
  static Map<String, String> publicReferer(Uri page, Uri target) {
    if (page.scheme == 'https' && target.scheme != 'https') return const {};
    return {
      'Referer': Uri(
        scheme: page.scheme,
        host: page.host,
        port: page.hasPort ? page.port : null,
        path: origin(page) == origin(target) ? page.path : '/',
      ).toString(),
    };
  }

  /// A list's credentials authorize its own origin, not URLs in its payload.
  static Map<String, String> playlistHeaders(
    Uri? listOrigin,
    Uri target,
    Map<String, String> headers,
  ) {
    if (listOrigin == null || origin(listOrigin) == origin(target)) {
      return sanitize(headers);
    }
    final result = <String, String>{};
    for (final entry in sanitize(headers).entries) {
      if (entry.key.toLowerCase() == 'user-agent') {
        result[entry.key] = entry.value;
      } else if (entry.key.toLowerCase() == 'origin') {
        final page = Uri.tryParse(entry.value);
        if (page != null &&
            {'http', 'https'}.contains(page.scheme) &&
            page.host.isNotEmpty &&
            page.userInfo.isEmpty) {
          result['Origin'] = Uri(
            scheme: page.scheme,
            host: page.host,
            port: page.hasPort ? page.port : null,
          ).toString().replaceFirst(RegExp(r'/$'), '');
        }
      } else if (entry.key.toLowerCase() == 'referer') {
        final page = Uri.tryParse(entry.value);
        if (page != null &&
            {'http', 'https'}.contains(page.scheme) &&
            page.host.isNotEmpty) {
          result.addAll(publicReferer(page, target));
        }
      }
    }
    return result;
  }

  /// An endpoint's credentials never authorize an arbitrary resolved media host.
  static Map<String, String> scopedHeaders(
    Uri endpoint,
    Uri target,
    Map<String, String> headers,
  ) => origin(endpoint) == origin(target) ? headers : const {};

  Map<String, String> get identityHeaders => {
    for (final origin in _origins.entries)
      for (final header in origin.value.entries)
        '${origin.key}/${header.key.toLowerCase()}': header.value,
  };
}
