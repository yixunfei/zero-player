import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as ast;
import 'package:html/dom.dart';

const _properties = {
  'color',
  'background-color',
  'font-family',
  'font-size',
  'font-style',
  'font-weight',
  'text-align',
  'text-decoration',
  'text-indent',
  'line-height',
  'letter-spacing',
  'word-spacing',
  'white-space',
  'vertical-align',
  'margin',
  'margin-top',
  'margin-bottom',
  'margin-left',
  'margin-right',
  'padding',
  'padding-top',
  'padding-bottom',
  'padding-left',
  'padding-right',
  'border',
  'border-width',
  'border-style',
  'border-color',
  'border-collapse',
  'width',
  'height',
  'max-width',
  'list-style-type',
  'direction',
  'writing-mode',
};
Map<String, String> safeDeclarations(String text) {
  final result = <String, String>{};
  for (final part in text.split(';')) {
    final colon = part.indexOf(':');
    if (colon < 0) continue;
    final key = part.substring(0, colon).trim().toLowerCase();
    final value = part.substring(colon + 1).trim();
    if (!_properties.contains(key) ||
        value.length > 256 ||
        RegExp(
          r'url|expression|var\(|@|[\\<>]',
          caseSensitive: false,
        ).hasMatch(value)) {
      continue;
    }
    result[key] = value;
  }
  return result;
}

/// Apply only document-local rules. Never load CSS imports, fonts or URL values.
void applyEpubStyles(Document doc, List<String> sheets) {
  final cascade = <Element, Map<String, (int, String)>>{};
  for (final sheet in sheets) {
    if (sheet.length > 1024 * 1024) continue;
    for (final rule
        in css.parse(sheet).topLevels.whereType<ast.RuleSet>().take(4000)) {
      final declarations = safeDeclarations(
        rule.declarationGroup.span.text.replaceAll(RegExp(r'[{}]'), ''),
      );
      for (final selector in (rule.selectorGroup?.span?.text ?? '').split(
        ',',
      )) {
        if (selector.contains(':') || selector.trim().isEmpty) continue;
        final weight =
            '#'.allMatches(selector).length * 100 +
            RegExp(r'[.\[]').allMatches(selector).length * 10 +
            RegExp(r'(^|[ >+~])\w').allMatches(selector).length;
        try {
          for (final element in doc.querySelectorAll(selector.trim())) {
            final styles = cascade.putIfAbsent(element, () => {});
            for (final entry in declarations.entries) {
              final important = entry.value.contains('!important');
              final priority = weight + (important ? 10000 : 0);
              if (priority >= (styles[entry.key]?.$1 ?? -1)) {
                styles[entry.key] = (
                  priority,
                  entry.value.replaceAll('!important', '').trim(),
                );
              }
            }
          }
        } on Object {
          /* Unsupported selectors do not invalidate a book. */
        }
      }
    }
  }
  for (final element in doc.querySelectorAll('*')) {
    final styles = cascade[element] ?? {};
    for (final entry in safeDeclarations(
      element.attributes['style'] ?? '',
    ).entries) {
      final priority = entry.value.contains('!important') ? 11000 : 1000;
      if (priority >= (styles[entry.key]?.$1 ?? -1)) {
        styles[entry.key] = (
          priority,
          entry.value.replaceAll('!important', '').trim(),
        );
      }
    }
    element.attributes.remove('style');
    if (styles.isNotEmpty) {
      element.attributes['style'] = styles.entries
          .map((e) => '${e.key}:${e.value.$2}')
          .join(';');
    }
  }
}
