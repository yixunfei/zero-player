import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Converts third-party display text to plain text; never use for IDs or URLs.
String displayText(String value) {
  var text = value;
  for (
    var pass = 0;
    pass < 4 && (text.contains('<') || text.contains('&'));
    pass++
  ) {
    final fragment = html.parseFragment(text);
    for (final node in fragment.querySelectorAll('script,style,template')) {
      node.remove();
    }
    for (final node in fragment.querySelectorAll(
      'br,p,div,li,tr,h1,h2,h3,h4,h5,h6,section,article,blockquote',
    )) {
      node.append(Text(' '));
    }
    final decoded = fragment.text ?? '';
    if (decoded == text) break;
    text = decoded;
  }
  return String.fromCharCodes(
    text.runes.where(_visibleRune),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _visibleRune(int rune) {
  if (rune < 32) return rune == 9 || rune == 10 || rune == 13;
  return rune != 127 &&
      rune != 0x200b &&
      rune != 0x200e &&
      rune != 0x200f &&
      rune != 0xfeff &&
      !(rune >= 0x202a && rune <= 0x202e) &&
      !(rune >= 0x2060 && rune <= 0x2069);
}
