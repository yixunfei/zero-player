import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import '../data/epub_styles.dart';

/// A glyph, paragraph boundary, or an intact illustration/technical block.
class VerticalItem {
  const VerticalItem(this.text, this.style, {this.ruby = '', this.html});
  final String text, ruby;
  final TextStyle style;
  final String? html;
  double get extent => (style.fontSize ?? 21) * 1.25;
}

List<VerticalItem> verticalEpubItems(String source, TextStyle base) {
  final items = <VerticalItem>[];
  void boundary() {
    if (items.isNotEmpty && items.last.text != '\n') {
      items.add(VerticalItem('\n', base));
    }
  }

  void visit(dom.Node node, TextStyle inherited) {
    if (node is dom.Text) {
      for (final char in node.text.replaceAll(RegExp(r'\s+'), ' ').characters) {
        if (char == ' ' && (items.isEmpty || items.last.text == '\n')) continue;
        items.add(VerticalItem(char, inherited));
      }
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName;
    if (['rt', 'rp', 'script', 'style'].contains(tag)) return;
    final style = _elementStyle(node, inherited);
    if (['img', 'figure', 'pre', 'table'].contains(tag)) {
      boundary();
      items.add(VerticalItem('', style, html: node.outerHtml));
      return;
    }
    if (tag == 'ruby') {
      _rubyItems(node, style, items);
      return;
    }
    final block = ['p', 'div', 'section', 'h1', 'h2', 'h3', 'li', 'blockquote'];
    if (block.contains(tag) || tag == 'br') boundary();
    for (final child in node.nodes) {
      visit(child, style);
    }
    if (block.contains(tag)) boundary();
  }

  for (final node in html.parseFragment(source).nodes) {
    visit(node, base);
  }
  return items;
}

void _rubyItems(dom.Element node, TextStyle style, List<VerticalItem> items) {
  // Each rt annotates the preceding base group, including EPUB rb/rt pairs.
  var pending = StringBuffer();
  void flush(String annotation) {
    final bases = pending.toString().characters.toList();
    final notes = annotation.characters.toList();
    for (var i = 0; i < bases.length; i++) {
      final start = (i * notes.length / bases.length).floor();
      final end = ((i + 1) * notes.length / bases.length).floor();
      items.add(
        VerticalItem(bases[i], style, ruby: notes.sublist(start, end).join()),
      );
    }
    pending = StringBuffer();
  }

  for (final child in node.nodes) {
    if (child is dom.Element && child.localName == 'rp') continue;
    if (child is dom.Element && child.localName == 'rt') {
      flush(child.text);
    } else {
      pending.write(child.text);
    }
  }
  flush('');
}

TextStyle _elementStyle(dom.Element node, TextStyle base) {
  final css = safeDeclarations(node.attributes['style'] ?? '');
  final tag = node.localName;
  final bold =
      ['b', 'strong', 'h1', 'h2', 'h3'].contains(tag) ||
      ['bold', '700', '800', '900'].contains(css['font-weight']);
  final italic = ['i', 'em'].contains(tag) || css['font-style'] == 'italic';
  final color = css['color'];
  Color? ink;
  if (color != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
    ink = Color(0xff000000 | int.parse(color.substring(1), radix: 16));
  }
  final size = css['font-size'] ?? '';
  final number = double.tryParse(size.replaceAll(RegExp('[^0-9.]'), ''));
  final font = number == null
      ? base.fontSize
      : size.endsWith('em')
      ? number * (base.fontSize ?? 21)
      : size.endsWith('%')
      ? number * (base.fontSize ?? 21) / 100
      : number;
  return base.copyWith(
    fontWeight: bold ? FontWeight.bold : null,
    fontStyle: italic ? FontStyle.italic : null,
    fontSize: font?.clamp(10, 48),
    color: ink,
  );
}

typedef VerticalColumn = ({List<VerticalItem> items, double width});
typedef VerticalPage = ({List<VerticalColumn> columns, String? html});

List<VerticalPage> paginateVertical(List<VerticalItem> items, Size size) {
  final pages = <VerticalPage>[];
  var columns = <VerticalColumn>[];
  var column = <VerticalItem>[];
  double usedWidth = 0, usedHeight = 0, width = 0;
  void flushPage() {
    if (columns.isEmpty) return;
    pages.add((columns: columns, html: null));
    columns = [];
    usedWidth = 0;
  }

  void flushColumn() {
    if (column.isEmpty) return;
    if (usedWidth + width > size.width && columns.isNotEmpty) flushPage();
    columns.add((items: column, width: math.min(width, size.width)));
    usedWidth += width;
    column = [];
    usedHeight = 0;
    width = 0;
  }

  for (final item in items) {
    if (item.html != null) {
      flushColumn();
      flushPage();
      pages.add((columns: [], html: item.html));
    } else if (item.text == '\n') {
      flushColumn();
    } else {
      if (usedHeight + item.extent > size.height) flushColumn();
      column.add(item);
      usedHeight += item.extent;
      width = math.max(width, (item.style.fontSize ?? 21) * 1.8);
    }
  }
  flushColumn();
  flushPage();
  return pages.isEmpty ? [(columns: [], html: null)] : pages;
}
