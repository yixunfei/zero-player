/// Split rule operators outside selectors, quoted strings and templates.
List<String> splitLegadoRule(String input, String operator) {
  final parts = <String>[];
  final expected = <String>[];
  String? quote;
  var start = 0;
  for (var index = 0; index < input.length; index++) {
    final char = input[index];
    if (char == r'\') {
      index++;
      continue;
    }
    if (quote != null) {
      if (char == quote) quote = null;
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
    } else if (expected.isEmpty && input.startsWith(operator, index)) {
      parts.add(input.substring(start, index).trim());
      index += operator.length - 1;
      start = index + 1;
    } else if (const {'[', '(', '{'}.contains(char)) {
      expected.add(const {'[': ']', '(': ')', '{': '}'}[char]!);
    } else if (expected.isNotEmpty && char == expected.last) {
      expected.removeLast();
    }
  }
  return [...parts, input.substring(start).trim()];
}

final legadoScriptMarker = RegExp(r'<js>|@js:', caseSensitive: false);
