import 'dart:convert';

/// JSON comments and trailing commas only; no evaluation or single-quote JS.
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
    if (char == '/' && i + 1 < input.length) {
      if (input[i + 1] == '/') {
        while (i < input.length && input[i] != '\n') {
          i++;
        }
        output.write('\n');
        continue;
      }
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
