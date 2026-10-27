import '../../../core/network/document_client.dart';
import '../../../core/text/display_text.dart';
import '../domain/catalog_item.dart';
import '../domain/vod_provider.dart';
import 'kanju_client.dart';
import 'website_transport.dart';

final class KanjuProvider implements VodProvider {
  const KanjuProvider(this.transport);
  final WebsiteTransport transport;
  KanjuClient get client => KanjuClient(transport);
  static const categories = {
    'movie': '电影',
    'series': '电视剧',
    'anime': '动漫',
    'variety': '综艺',
    'documentary': '纪录片',
  };

  Future<CatalogPage> _listing({
    String query = '',
    String category = '',
    int page = 1,
  }) async {
    final uri = transport
        .url('/v1/browse/catalog')
        .replace(
          queryParameters: {
            'page': '$page',
            'limit': '20',
            if (query.isNotEmpty) 'q': query,
            if (query.isEmpty) 'intent': 'latest_catalog',
            if (category.isNotEmpty) 'kind': category,
          },
        );
    final data = await client.get(uri);
    if (data['cards'] is! List) throw const FormatException('看剧AI片单结构已变化');
    final pagination = data['pagination'] as Map? ?? {};
    return CatalogPage(
      (data['cards'] as List).whereType<Map>().map(parse).toList(),
      pagination['has_more'] == true ? page + 1 : page,
    );
  }

  @override
  Future<CatalogPage> search(String query, {int page = 1}) =>
      _listing(query: query, page: page);
  @override
  Future<CatalogBrowse> browse({String category = '', int page = 1}) async =>
      CatalogBrowse(
        await _listing(category: category, page: page),
        categories: categories,
      );

  @override
  Future<CatalogItem> detail(String remoteId) async {
    final path = '/v1/catalog/${Uri.encodeComponent(remoteId)}';
    final data = await client.get(transport.url(path));
    final episodes = <Map>[
      ...(data['episodes'] as List? ?? []).whereType<Map>(),
    ];
    var pagination = data['episode_pagination'] as Map? ?? {};
    for (var page = 0; pagination['has_more'] == true; page++) {
      if (page >= 49 || episodes.length >= 10000) {
        throw const FormatException('剧集超过加载上限');
      }
      final next = await client.get(
        transport
            .url('$path/episodes')
            .replace(
              queryParameters: {'offset': '${episodes.length}', 'limit': '200'},
            ),
      );
      final batch = (next['episodes'] as List? ?? []).whereType<Map>().toList();
      if (batch.isEmpty) throw const FormatException('剧集分页没有前进');
      episodes.addAll(batch);
      pagination =
          next['episode_pagination'] as Map? ??
          next['pagination'] as Map? ??
          {};
    }
    var lines = <Map>[];
    if (episodes.isNotEmpty && episodes.first['token'] is String) {
      final playback = await client.get(
        transport.url(
          '/v1/playback/resolve/${Uri.encodeComponent(episodes.first['token'] as String)}',
        ),
      );
      lines = (playback['line_options'] as List? ?? [])
          .whereType<Map>()
          .where(_directLine)
          .toList();
    }
    return parse({...data, 'episodes': episodes, 'direct_lines': lines});
  }

  CatalogItem parse(Map row) {
    String text(String key) =>
        row[key] is List ? (row[key] as List).join(' / ') : '${row[key] ?? ''}';
    String clean(String key) => displayText(text(key));
    final episodes = <Episode>[];
    for (final ep in (row['episodes'] as List? ?? []).whereType<Map>()) {
      final token = '${ep['token'] ?? ''}';
      if (token.isEmpty) continue;
      episodes.add(
        Episode(
          displayText('${ep['title'] ?? ep['number'] ?? '正片'}'),
          transport.url('/v1/playback/resolve/${Uri.encodeComponent(token)}'),
          requiresResolution: true,
        ),
      );
    }
    return CatalogItem(
      sourceId: transport.source.id,
      id: text('id'),
      title: clean('title'),
      poster: text('poster_url'),
      year: clean('year'),
      category: categories[text('content_kind')] ?? clean('content_kind'),
      area: clean('area'),
      description: clean('description'),
      remarks: clean('remarks'),
      actors: clean('actors'),
      director: clean('directors'),
      lines: episodes.isEmpty ? [] : _lines(row, episodes),
    );
  }

  bool _directLine(Map line) =>
      line['resolved'] == true &&
      line['resolve_required'] != true &&
      (num.tryParse('${line['minimum_user_level'] ?? 0}') ?? 0) == 0;

  List<PlayLine> _lines(Map row, List<Episode> episodes) {
    final lines = (row['direct_lines'] as List? ?? []).whereType<Map>();
    if (lines.isEmpty) return [PlayLine('看剧AI · 直连资源', episodes)];
    final seen = <String>{};
    return [
      for (final line in lines)
        if (line['provider_id'] is String &&
            seen.add(line['provider_id'] as String))
          PlayLine(
            displayText(
              '${line['provider_name'] ?? line['label'] ?? line['provider_id']}',
            ),
            [
              for (final episode in episodes)
                Episode(
                  episode.label,
                  episode.uri.replace(
                    queryParameters: {
                      'provider_id': line['provider_id'] as String,
                    },
                  ),
                  requiresResolution: true,
                ),
            ],
          ),
    ];
  }

  @override
  Future<ResolvedMedia> resolve(Episode episode) async {
    transport.requireSameOrigin(episode.uri);
    if (!episode.uri.path.startsWith('/v1/playback/resolve/')) {
      throw const FormatException('播放接口无效');
    }
    final data = await client.get(episode.uri);
    for (final line in (data['line_options'] as List? ?? []).whereType<Map>()) {
      final requested = episode.uri.queryParameters['provider_id'];
      if (requested != null && requested != line['provider_id']) continue;
      if (line['resolved'] != true ||
          line['resolve_required'] == true ||
          (num.tryParse('${line['minimum_user_level'] ?? 0}') ?? 0) > 0) {
        continue;
      }
      final uri = Uri.tryParse('${line['url'] ?? ''}');
      if (uri != null &&
          {'https', 'http'}.contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          RegExp(r'[.](m3u8|mp4|flv)$').hasMatch(uri.path)) {
        return ResolvedMedia(uri);
      }
    }
    throw const RemoteFailure(
      FailureKind.unsupported,
      '此集没有公开直连线路；原站解析或账户线路暂不支持',
    );
  }
}
