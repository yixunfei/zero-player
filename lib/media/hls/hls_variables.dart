/// Expands playlist variables without executing expressions or changing URL
/// identity. Imported values come only from the explicitly linked parent.
({List<String> lines, Map<String, String> variables}) expandHlsVariables(
  List<String> input,
  Uri base,
  Map<String, String> inherited,
) {
  final values = <String, String>{};
  final output = <String>[];
  var expandedLength = 0;
  if (input.length > 40000) {
    throw const FormatException('HLS 清单行数超限');
  }
  for (final raw in input) {
    final line = raw.trim();
    if (!line.startsWith('#EXT-X-DEFINE:')) {
      var lineLength = raw.length;
      if (lineLength > 65536) throw const FormatException('HLS 清单行过长');
      output.add(
        line.startsWith('#')
            ? line.startsWith('#EXT')
                  ? raw.replaceAllMapped(RegExp(r'"[^"]*"'), (match) {
                      final result = _expand(match[0]!, values);
                      lineLength += result.length - match[0]!.length;
                      if (lineLength > 65536) {
                        throw const FormatException('HLS 变量展开过长');
                      }
                      return result;
                    })
                  : raw
            : _expand(raw, values),
      );
      expandedLength += output.last.length + 1;
      if (expandedLength > 2 * 1024 * 1024) {
        throw const FormatException('HLS 变量展开后超过大小限制');
      }
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
    final expanded = _expand(value, values);
    if (expanded.length > 8192 ||
        RegExp(r'[\x00-\x1f\x7f"]').hasMatch(expanded)) {
      throw const FormatException('HLS 变量包含不安全内容或超过大小限制');
    }
    values[name] = expanded;
    // All references are expanded before the native player sees the playlist.
    // Keeping DEFINE/IMPORT after rewriting would require its old parent scope.
  }
  return (lines: output, variables: Map.unmodifiable(values));
}

String _expand(String value, Map<String, String> variables) {
  var length = value.length;
  if (length > 65536) throw const FormatException('HLS 清单行过长');
  return value.replaceAllMapped(RegExp(r'\{\$([a-zA-Z0-9_-]+)\}'), (match) {
    final resolved = variables[match[1]];
    if (resolved == null) {
      throw const FormatException('Undefined HLS variable');
    }
    length += resolved.length - match[0]!.length;
    if (length > 65536) throw const FormatException('HLS 变量展开过长');
    return resolved;
  });
}
