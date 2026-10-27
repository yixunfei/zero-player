import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import '../../../core/text/display_text.dart';
import '../domain/catalog_item.dart';

/// Parses data only; remote scripts and parser services are never executed.
final class MacCmsHtmlParser {
  const MacCmsHtmlParser(this.sourceId, this.base);
  final String sourceId;
  final Uri base;

  CatalogPage listing(String text, {int page = 1}) {
    final doc = html.parse(text);
    final items = <String, CatalogItem>{};
    for (final link in doc.querySelectorAll('a[href*="/voddetail/"]')) {
      final id = RegExp(
        r'/voddetail/([0-9]+)[.]html',
      ).firstMatch(link.attributes['href'] ?? '')?[1];
      if (id == null || items.containsKey(id)) continue;
      final image = link.querySelector('img');
      final title = displayText(
        link.attributes['title'] ??
            image?.attributes['alt'] ??
            link.text.trim(),
      );
      if (title.isEmpty) continue;
      items[id] = CatalogItem(
        sourceId: sourceId,
        id: id,
        title: title,
        poster: _poster(image),
        remarks: displayText(
          link.querySelector('.module-item-note')?.text ?? '',
        ),
      );
    }
    var pages = page;
    for (final link in doc.querySelectorAll(
      '#page a, .page a, .pagination a',
    )) {
      final label = link.text.trim();
      final number = int.tryParse(label);
      if (number != null && number > pages) pages = number;
      if (label.contains('下一页') &&
          link.attributes['href'] != null &&
          link.attributes['href'] != '#' &&
          !link.classes.contains('disabled')) {
        pages = pages < page + 1 ? page + 1 : pages;
      }
    }
    if (items.isEmpty &&
        doc.querySelector('form[action*="vodsearch"]') == null) {
      throw const FormatException('网站未返回可识别的影片列表，可能需要验证');
    }
    return CatalogPage(items.values.toList(), pages.clamp(1, 10000));
  }

  CatalogItem detail(String text, String id) {
    final doc = html.parse(text);
    final title = displayText(doc.querySelector('h1')?.text ?? '');
    if (title.isEmpty) throw const FormatException('影片详情结构已变化');
    final groups = <String, List<Episode>>{};
    final seen = <Uri>{};
    for (final a in doc.querySelectorAll('a[href*="/vodplay/"]')) {
      final match = RegExp(
        r'/vodplay/([0-9]+)-([0-9]+)-([0-9]+)[.]html',
      ).firstMatch(a.attributes['href'] ?? '');
      if (match == null || match[1] != id) continue;
      final uri = base.resolve(match[0]!);
      if (!seen.add(uri)) continue;
      final label = a.querySelector('span')?.text.trim() ?? a.text.trim();
      groups
          .putIfAbsent(match[2]!, () => [])
          .add(
            Episode(
              label.isEmpty || label.contains('立即播放')
                  ? '第${match[3]}集'
                  : displayText(label),
              uri,
              requiresResolution: true,
            ),
          );
    }
    final names = doc
        .querySelectorAll('.module-tab-item')
        .map((e) => e.nodes.whereType<Text>().map((n) => n.text).join().trim())
        .toList();
    final lines = <PlayLine>[];
    var index = 0;
    for (final entry in groups.entries) {
      lines.add(
        PlayLine(
          index < names.length && names[index].isNotEmpty
              ? displayText(names[index])
              : '线路 ${entry.key}',
          entry.value,
        ),
      );
      index++;
    }
    return CatalogItem(
      sourceId: sourceId,
      id: id,
      title: title,
      poster: _poster(
        doc.querySelector('.module-info-poster img, .module-item-pic img'),
      ),
      description: displayText(
        doc
                .querySelector('.module-info-introduction, .vod_content')
                ?.text
                .trim() ??
            '',
      ),
      lines: lines,
    );
  }

  String _poster(Element? image) {
    final value =
        image?.attributes['data-original'] ??
        image?.attributes['data-src'] ??
        image?.attributes['src'] ??
        '';
    return value.isEmpty ? '' : base.resolve(value).toString();
  }
}

Uri parseMacCmsPlayer(String text, Uri page) {
  final match = RegExp(r'var +player_[a-zA-Z0-9_]+ *= *').firstMatch(text);
  if (match == null) throw const FormatException('页面没有可识别的播放配置');
  final input = text.substring(match.end);
  var depth = 0;
  var quoted = false;
  var escaped = false;
  var end = -1;
  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (c == 92) {
        escaped = true;
      } else if (c == 34) {
        quoted = false;
      }
    } else if (c == 34) {
      quoted = true;
    } else if (c == 123) {
      depth++;
    } else if (c == 125 && --depth == 0) {
      end = i + 1;
      break;
    }
  }
  if (end < 0) throw const FormatException('播放配置不完整');
  final data = jsonDecode(input.substring(0, end)) as Map;
  var value = '${data['url'] ?? ''}';
  final encryption = '${data['encrypt'] ?? 0}';
  if (encryption == '2') value = utf8.decode(base64.decode(value));
  if (encryption == '1' || encryption == '2') {
    value = Uri.decodeComponent(value);
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      !RegExp(
        r'[.](m3u8|mp4|flv|mkv|webm|ts)$',
        caseSensitive: false,
      ).hasMatch(uri.path)) {
    throw const FormatException('此线路需要外部解析，请切换直连线路');
  }
  return uri;
}
