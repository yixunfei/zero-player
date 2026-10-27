/// Credentials and custom headers are scoped to the exact original origin.
/// A redirect or HLS child on another origin must supply its own explicit scope.
final class HeaderPolicy {
  HeaderPolicy(Map<Uri, Map<String, String>> origins)
    : _origins = {
        for (final entry in origins.entries)
          origin(entry.key): Map<String, String>.unmodifiable(entry.value),
      };

  final Map<String, Map<String, String>> _origins;

  static String origin(Uri uri) => '${uri.scheme}://${uri.host}:${uri.port}';

  Map<String, String> forUri(Uri uri) => _origins[origin(uri)] ?? const {};

  Map<String, String> get identityHeaders => {
    for (final origin in _origins.entries)
      for (final header in origin.value.entries)
        '${origin.key}/${header.key.toLowerCase()}': header.value,
  };
}
