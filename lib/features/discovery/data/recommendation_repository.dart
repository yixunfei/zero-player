import 'dart:convert';
import '../../../core/text/display_text.dart';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/persistence/app_database.dart';

final class Recommendation {
  const Recommendation(
    this.title,
    this.poster,
    this.subtitle, {
    this.id = '',
    this.description = '',
  });
  final String title;
  final String poster;
  final String subtitle;
  final String id;
  final String description;
  String get identity => id.isNotEmpty ? id : title.trim().toLowerCase();
  Map<String, String> toJson() => {
    'title': title,
    'poster': poster,
    'subtitle': subtitle,
    'id': id,
    'description': description,
  };
}

final class Recommendations {
  const Recommendations(
    this.items, {
    this.cached = false,
    this.message,
    this.categories = const {},
    this.hasMore = false,
  });
  final List<Recommendation> items;
  final bool cached;
  final Map<String, String> categories;
  final String? message;
  final bool hasMore;
}

const recommendationNames = {
  'douban': '豆瓣精选',
  'bangumi': 'Bangumi 新番',
  'hot': '影视榜单',
  'off': '推荐已关闭',
};
const recommendationPageSize = 24;

final class RecommendationRepository {
  const RecommendationRepository(
    this.network,
    this.db, {
    this.endpoint = recommendationUri,
  });
  final DocumentClient network;
  final AppDatabase db;
  final Uri Function(String, String, int) endpoint;

  Future<Recommendations> load(
    String provider, {
    String type = 'movie',
    int page = 1,
    CancellationToken? cancellation,
  }) async {
    if (provider == 'off' || (page > 1 && provider != 'douban')) {
      return const Recommendations([]);
    }
    if (page < 1) throw ArgumentError.value(page, 'page');
    final key = '$provider:$type';
    try {
      cancellation?.check();
      final data = (await network.get(
        endpoint(provider, type, page),
        headers: {'User-Agent': 'ZeroPlayer/0.1 (local media client)'},
        cancellation: cancellation,
      )).json;
      cancellation?.check();
      final items = parseRecommendations(provider, data, type: type);
      if (items.isEmpty && page == 1) throw const FormatException('推荐列表为空');
      if (page == 1) await _cache(key, items);
      cancellation?.check();
      return Recommendations(
        items,
        hasMore: provider == 'douban' && items.length >= recommendationPageSize,
      );
    } catch (_) {
      cancellation?.check();
      if (page > 1) rethrow;
      return _cached(key);
    }
  }

  Future<void> _cache(String key, List<Recommendation> items) async {
    // Cache only first pages, capped by both age and count; no unbounded page log.
    await db.atomic(() async {
      await db.customStatement(
        'INSERT OR REPLACE INTO recommendation_cache VALUES(?,?,?)',
        [
          key,
          jsonEncode(items.map((i) => i.toJson()).toList()),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      await db.customStatement(
        'DELETE FROM recommendation_cache WHERE updated_at < ?',
        [
          DateTime.now()
              .subtract(const Duration(days: 7))
              .millisecondsSinceEpoch,
        ],
      );
      await db.customStatement(
        'DELETE FROM recommendation_cache WHERE provider NOT IN '
        '(SELECT provider FROM recommendation_cache ORDER BY updated_at DESC LIMIT 32)',
      );
    });
  }

  Future<Recommendations> _cached(String key) async {
    final cached = await db.rows(
      'SELECT payload FROM recommendation_cache WHERE provider=? AND updated_at>=?',
      [
        key,
        DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch,
      ],
    );
    if (cached.isNotEmpty) {
      try {
        final list = jsonDecode(cached.first['payload'] as String) as List;
        return Recommendations(
          [
            for (final r in list.whereType<Map>().take(recommendationPageSize))
              Recommendation(
                displayText('${r['title'] ?? ''}'),
                '${r['poster'] ?? ''}',
                displayText('${r['subtitle'] ?? ''}'),
                id: '${r['id'] ?? ''}',
                description: displayText('${r['description'] ?? ''}'),
              ),
          ],
          cached: true,
          message: '当前显示上次成功获取的推荐；刷新可重试联网',
        );
      } on FormatException {
        /* Discard corrupt cache and show a recoverable state. */
      } on TypeError {
        /* Old or malformed cache is not a fatal startup error. */
      }
    }
    return const Recommendations([], message: '推荐暂不可用，可刷新重试、切换频道或搜索影片');
  }
}

Uri recommendationUri(
  String provider,
  String type,
  int page,
) => switch (provider) {
  'bangumi' => Uri.parse('https://api.bgm.tv/calendar'),
  'hot' => Uri.https(
    '60s.viki.moe',
    type == 'baidu'
        ? '/v2/baidu/teleplay'
        : '/v2/douban/weekly/${hotCategories.containsKey(type) ? type : 'movie'}',
  ),
  _ => Uri.https('movie.douban.com', '/j/search_subjects', {
    'type': movieCategories.contains(type) ? 'movie' : 'tv',
    'tag': {'movie', 'tv'}.contains(type)
        ? '热门'
        : doubanCategories[type] ?? '热门',
    'page_limit': '$recommendationPageSize',
    'page_start': '${(page - 1) * recommendationPageSize}',
  }),
};

const hotCategories = {
  'movie': '豆瓣电影',
  'tv_chinese': '华语剧集',
  'tv_global': '全球剧集',
  'show_chinese': '国内综艺',
  'show_global': '全球综艺',
  'baidu': '百度热播剧',
};
const doubanCategories = {
  'movie': '热门电影',
  'tv': '热门剧集',
  'animation': '日本动画',
  'us': '美剧',
  'uk': '英剧',
  'cn': '国产剧',
  'kr': '韩剧',
  'jp': '日剧',
  'variety': '综艺',
  'documentary': '纪录片',
  'short': '短剧',
  'children': '儿童',
  'action': '动作',
  'comedy': '喜剧',
  'science': '科幻',
  'suspense': '悬疑',
  'animated_movie': '动画',
};
const movieCategories = {
  'movie',
  'action',
  'comedy',
  'science',
  'suspense',
  'animated_movie',
  'children',
};

Map<String, String> recommendationCategories(String provider) =>
    switch (provider) {
      'hot' => hotCategories,
      'bangumi' => const {
        'all': '整周新番',
        '1': '周一',
        '2': '周二',
        '3': '周三',
        '4': '周四',
        '5': '周五',
        '6': '周六',
        '7': '周日',
      },
      'off' => const {'movie': '推荐已关闭'},
      _ => doubanCategories,
    };

List<Recommendation> parseRecommendations(
  String provider,
  Object? raw, {
  String type = 'movie',
}) {
  if (provider == 'bangumi' && raw is List) {
    return [
      for (final day in raw.whereType<Map>())
        if (int.tryParse(type) == null ||
            (day['weekday'] as Map?)?['id'] == int.parse(type))
          for (final item in (day['items'] as List? ?? []).whereType<Map>())
            Recommendation(
              displayText(
                '${item['name_cn'] == '' ? item['name'] : item['name_cn'] ?? item['name'] ?? ''}',
              ),
              '${(item['images'] as Map?)?['large'] ?? ''}',
              displayText('${(day['weekday'] as Map?)?['cn'] ?? ''}'),
              id: '${item['id'] ?? ''}',
            ),
    ].where((item) => item.title.trim().isNotEmpty).toList();
  }
  if (raw is! Map) return [];
  final list = raw['subjects'] ?? raw['data'];
  if (list is! List) return [];
  return [
    for (final item in list.whereType<Map>())
      Recommendation(
        displayText('${item['title'] ?? item['name'] ?? ''}'),
        '${item['cover'] ?? item['poster'] ?? item['cover_url'] ?? ''}'.trim(),
        displayText('${item['rating'] ?? item['rate'] ?? item['score'] ?? ''}'),
        id: '${item['id'] ?? ''}',
        description: displayText(
          '${item['summary'] ?? item['description'] ?? ''}',
        ),
      ),
  ].where((item) => item.title.isNotEmpty).toList();
}
