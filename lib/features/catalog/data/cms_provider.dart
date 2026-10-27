import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/text/display_text.dart';
import '../../../core/network/request_scheduler.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../sources/domain/video_source.dart';
import '../domain/catalog_item.dart';
import '../domain/vod_provider.dart';

final class CmsProvider implements VodProvider {
  const CmsProvider(
    this.source,
    this.network, {
    this.cancellation,
    this.priority = RequestPriority.interactive,
    this.onActivity,
  });
  final VideoSource source;
  final DocumentClient network;
  final CancellationToken? cancellation;
  final RequestPriority priority;
  final void Function(bool active)? onActivity;

  @override
  Future<CatalogBrowse> browse({String category = '', int page = 1}) async {
    final data = await browseData(category: category, page: page);
    return CatalogBrowse(
      CatalogPage(
        (data['list'] as List).whereType<Map>().map(parse).toList(),
        (int.tryParse('${data['pagecount']}') ?? 1).clamp(1, 10000),
      ),
      categories: {
        for (final row in (data['class'] as List? ?? []).whereType<Map>())
          '${row['type_id']}': displayText('${row['type_name'] ?? ''}'),
      },
      metadata: data,
    );
  }

  @override
  Future<ResolvedMedia> resolve(Episode episode) async {
    if (!episode.directlyPlayable) {
      throw const RemoteFailure(FailureKind.unsupported, '此 CMS 线路需要外部解析');
    }
    return ResolvedMedia(episode.uri, headers: source.headers);
  }

  Future<Map> _request(Map<String, String> query) async {
    final uri = source.endpoint.replace(
      queryParameters: {...source.endpoint.queryParameters, ...query},
    );
    final doc = await network.get(
      uri,
      headers: source.headers,
      priority: priority,
      cancellation: cancellation,
      maxBytes: 4 * 1024 * 1024,
      onActivity: onActivity,
    );
    try {
      final json = doc.bytes.length > 65536
          ? await compute(decodeCatalogJson, doc.text)
          : doc.json;
      if (json is! Map || json['list'] is! List) throw const FormatException();
      return json;
    } on FormatException {
      throw const RemoteFailure(FailureKind.invalid, '接口没有返回有效的影片列表');
    }
  }

  Future<Map> browseData({String category = '', int page = 1}) => _request({
    'ac': 'detail',
    'pg': '$page',
    if (category.isNotEmpty) 't': category,
  });

  @override
  Future<CatalogPage> search(String query, {int page = 1}) async {
    final data = await _request({'ac': 'detail', 'wd': query, 'pg': '$page'});
    return CatalogPage(
      (data['list'] as List).whereType<Map>().map(parse).toList(),
      (int.tryParse('${data['pagecount']}') ?? 1).clamp(1, 10000),
    );
  }

  @override
  Future<CatalogItem> detail(String remoteId) async {
    final data = await _request({'ac': 'detail', 'ids': remoteId});
    final list = (data['list'] as List).whereType<Map>();
    final exact = list.where((row) => '${row['vod_id']}' == remoteId);
    if (exact.isEmpty) {
      throw const RemoteFailure(FailureKind.invalid, '影片详情已不可用');
    }
    return parse(exact.first);
  }

  CatalogItem parse(Map row) {
    String text(String key) => row[key]?.toString() ?? '';
    final names = text('vod_play_from').split(r'$$$');
    final groups = text('vod_play_url').split(r'$$$');
    final lines = <PlayLine>[];
    for (var i = 0; i < groups.length; i++) {
      final episodes = <Episode>[];
      for (final raw in groups[i].split('#')) {
        if (raw.trim().isEmpty) continue;
        final divider = raw.indexOf(r'$');
        final label = divider < 0 ? '正片' : raw.substring(0, divider).trim();
        final address = divider < 0 ? raw : raw.substring(divider + 1);
        final uri = Uri.tryParse(address.trim());
        if (uri != null) episodes.add(Episode(displayText(label), uri));
      }
      if (episodes.isNotEmpty) {
        lines.add(
          PlayLine(
            i < names.length && names[i].isNotEmpty
                ? displayText(names[i])
                : '线路 ${i + 1}',
            episodes,
          ),
        );
      }
    }
    return CatalogItem(
      sourceId: source.id,
      id: text('vod_id'),
      title: displayText(text('vod_name')),
      poster: text('vod_pic').trim().isEmpty
          ? ''
          : source.endpoint.resolve(text('vod_pic').trim()).toString(),
      year: displayText(text('vod_year')),
      category: displayText(text('type_name')),
      area: displayText(text('vod_area')),
      remarks: displayText(text('vod_remarks')),
      description: displayText(text('vod_content')),
      actors: displayText(text('vod_actor')),
      director: displayText(text('vod_director')),
      lines: List.unmodifiable(lines),
    );
  }
}

Object? decodeCatalogJson(String text) => jsonDecode(text);
