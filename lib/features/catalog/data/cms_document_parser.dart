import 'dart:convert';
import 'package:xml/xml.dart';

/// Normalize MacCMS JSON and XML into one provider model.
Map decodeCmsDocument(String input) {
  final text = input.replaceFirst('\uFEFF', '').trimLeft();
  if (!text.startsWith('<')) {
    final data = jsonDecode(text);
    if (data is! Map || data['list'] is! List) {
      throw const FormatException('接口没有返回影片列表');
    }
    return data;
  }
  if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY')) {
    throw const FormatException('不支持含实体定义的采集文档');
  }
  final root = XmlDocument.parse(text).rootElement;
  if (!{'rss', 'data'}.contains(root.name.local)) {
    throw const FormatException('不是 MacCMS XML 文档');
  }
  final list = root.getElement('list');
  if (list == null) throw const FormatException('XML 缺少影片列表');
  return {
    'page': list.getAttribute('page') ?? '1',
    'pagecount': list.getAttribute('pagecount') ?? '1',
    'list': [for (final video in list.findElements('video')) _video(video)],
    'class': [
      for (final category
          in root.getElement('class')?.findElements('ty') ?? <XmlElement>[])
        {
          'type_id': category.getAttribute('id') ?? '',
          'type_name': category.innerText,
        },
    ],
  };
}

Map<String, Object?> _video(XmlElement video) {
  String field(String key) => video.getElement(key)?.innerText.trim() ?? '';
  final lines =
      video.getElement('dl')?.findElements('dd').toList() ?? <XmlElement>[];
  return {
    'vod_id': field('id'),
    'vod_name': field('name'),
    'vod_pic': field('pic'),
    'vod_year': field('year'),
    'type_name': field('type'),
    'vod_area': field('area'),
    'vod_remarks': field('note'),
    'vod_content': field('des'),
    'vod_actor': field('actor'),
    'vod_director': field('director'),
    'vod_play_from': lines
        .map((line) => line.getAttribute('flag') ?? '')
        .join(r'$$$'),
    'vod_play_url': lines.map((line) => line.innerText.trim()).join(r'$$$'),
  };
}
