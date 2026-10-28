/// Expands playlist variables without executing expressions or changing URL
/// identity. Imported values come only from the explicitly linked parent.
({List<String> lines, Map<String, String> variables}) expandHlsVariables(
  List<String> input,
  Uri base,
  Map<String, String> inherited,
) {
  final values = <String, String>{};
  final output = <String>[];
  for (final raw in input) {
    final line = raw.trim();
    if (!line.startsWith('#EXT-X-DEFINE:')) {
      output.add(
        line.startsWith('#')
            ? line.startsWith('#EXT')
                  ? raw.replaceAllMapped(
                      RegExp(r'"[^"]*"'),
                      (match) => _expand(match[0]!, values),
                    )
                  : raw
            : _expand(raw, values),
      );
      continue;
    }
    final attributes = <String, String>{
      for (final match in RegExp(r'([A-Z-]+)="([^"]*)"').allMatches(line))
        match[1]!: match[2]!,
    };
    final imported = attributes['IMPORT'];
    final parameter = attributes['QUERYPARAM'];
    final name = attributes['NAME'] ?? imported ?? parameter;
    final value = imported != null
        ? inherited[imported]
        : parameter != null
        ? base.queryParameters[parameter]
        : attributes['VALUE'];
    if (name == null ||
        value == null ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name) ||
        values.containsKey(name) ||
        values.length >= 64 ||
        value.length > 8192) {
      throw const FormatException('Invalid or unavailable HLS variable');
    }
    values[name] = _expand(value, values);
    // All references are expanded before the native player sees the playlist.
    // Keeping DEFINE/IMPORT after rewriting would require its old parent scope.
  }
  return (lines: output, variables: Map.unmodifiable(values));
}

String _expand(String value, Map<String, String> variables) =>
    value.replaceAllMapped(RegExp(r'\{\$([a-zA-Z0-9_-]+)\}'), (match) {
      final resolved = variables[match[1]];
      if (resolved == null) {
        throw const FormatException('Undefined HLS variable');
      }
      return resolved;
    });
