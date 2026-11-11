import 'dart:convert';

/// JSON comments and trailing commas only.
Object? decodeJsonc(String input) {
  final text = _stripComments(input);
  final output = StringBuffer();
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      output.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        quoted = false;
      }
    } else {
      if (char == '"') quoted = true;
      if (char == ',') {
        var next = i + 1;
        while (next < text.length && text[next].trim().isEmpty) {
          next++;
        }
        if (next < text.length && (text[next] == '}' || text[next] == ']')) {
          continue;
        }
      }
      output.write(char);
    }
  }
  return jsonDecode(output.toString());
}

String _stripComments(String input) {
  final output = StringBuffer();
  var quoted = false;
  var escaped = false;
  var depth = 0;
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (quoted) {
      output.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        quoted = false;
      }
      continue;
    }
    if (char == '"') quoted = true;
    if (char == '[' || char == '{') depth++;
    if (char == ']' || char == '}') depth--;
    if (depth > 64) throw const FormatException('JSON nesting limit exceeded');
    if (char == '#' ||
        (char == '/' && i + 1 < input.length && input[i + 1] == '/')) {
      while (i < input.length && input[i] != '\n') {
        i++;
      }
      output.write('\n');
      continue;
    }
    if (char == '/' && i + 1 < input.length) {
      if (input[i + 1] == '*') {
        final end = input.indexOf('*/', i + 2);
        if (end < 0) throw const FormatException('Unterminated JSON comment');
        output.write(' ');
        i = end + 1;
        continue;
      }
    }
    output.write(char);
  }
  return output.toString();
}

// Some catalogs have malformed unrelated sites or append a web footer. Recover
// only independently valid top-level arrays. Never infer URLs from broken rows.
Map<String, Object?> recoverLiveCatalogArrays(String input) {
  final text = _stripComments(input).trimLeft();
  if (!text.startsWith('{')) return {};
  const fields = {'lives', 'urls', 'storeHouse'};
  final result = <String, Object?>{};
  var depth = 0;
  var start = -1;
  var stringStart = -1;
  var escaped = false;
  String? field;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (stringStart >= 0) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        if (depth == 1) {
          final name = text.substring(stringStart + 1, i);
          field = null;
          if (fields.contains(name)) {
            var next = i + 1;
            while (next < text.length && text[next].trim().isEmpty) {
              next++;
            }
            if (next < text.length && text[next] == ':') field = name;
          }
        }
        stringStart = -1;
      }
      continue;
    }
    if (char == '"') {
      stringStart = i;
    } else if (char == '[' || char == '{') {
      if (depth == 1 && field != null && char == '[') start = i;
      depth++;
    } else if (char == ']' || char == '}') {
      if (--depth <= 0) return result;
      if (depth == 1) {
        if (start >= 0 && field != null) {
          try {
            result[field] = decodeJsonc(text.substring(start, i + 1));
          } on FormatException {
            // Keep other valid arrays in this document.
          }
        }
        start = -1;
        field = null;
      }
    } else if (depth == 1 && char == ',') {
      field = null;
    }
  }
  return {};
}
