final class CatalogItem {
  const CatalogItem({
    required this.sourceId,
    required this.id,
    required this.title,
    this.poster = '',
    this.year = '',
    this.category = '',
    this.categoryId = '',
    this.tags = '',
    this.area = '',
    this.remarks = '',
    this.description = '',
    this.actors = '',
    this.director = '',
    this.lines = const [],
  });
  final String sourceId;
  final String id;
  final String title;
  final String poster;
  final String year;
  final String category;
  final String categoryId;
  final String tags;
  final String area;
  final String remarks;
  final String description;
  final String actors;
  final String director;
  final List<PlayLine> lines;
  CatalogItem withCategory(String value) => CatalogItem(
    sourceId: sourceId,
    id: id,
    title: title,
    poster: poster,
    year: year,
    category: value,
    categoryId: categoryId,
    tags: tags,
    area: area,
    remarks: remarks,
    description: description,
    actors: actors,
    director: director,
    lines: lines,
  );
  String get groupKey =>
      '${title.toLowerCase().replaceAll(RegExp(r'[\s·•]'), '')}|$year|$category';
}

final class PlayLine {
  const PlayLine(this.name, this.episodes);
  final String name;
  final List<Episode> episodes;
}

final class Episode {
  const Episode(
    this.label,
    this.uri, {
    this.requiresResolution = false,
    this.headers,
  });
  final String label;
  final Uri uri;
  final bool requiresResolution;

  /// Scoped to this entry, since different channels may share a URI.
  final Map<String, String>? headers;
  bool get playable => requiresResolution || directlyPlayable;
  bool get directlyPlayable =>
      {'http', 'https'}.contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      !uri.queryParameters.containsKey('url') &&
      !uri.path.toLowerCase().endsWith('.html');
}

abstract interface class VodSearchProvider {
  Future<CatalogPage> search(String query, {int page = 1});
}

abstract interface class VodDetailProvider {
  Future<CatalogItem> detail(String remoteId);
}

final class CatalogPage {
  const CatalogPage(this.items, this.pageCount);
  final List<CatalogItem> items;
  final int pageCount;
}

/// Ambiguity is deliberately returned to the caller rather than guessing by
/// list index, especially for specials, movie cuts and different seasons.
List<int> matchingEpisodes(String label, List<Episode> candidates) {
  final normalized = _label(label);
  final exact = <int>[
    for (var i = 0; i < candidates.length; i++)
      if (_label(candidates[i].label) == normalized) i,
  ];
  if (exact.isNotEmpty) return exact;
  final number = semanticEpisode(label);
  if (number == null) return [];
  return [
    for (var i = 0; i < candidates.length; i++)
      if (semanticEpisode(candidates[i].label) == number) i,
  ];
}

String _label(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[\s._-]'), '');

String? semanticEpisode(String text) {
  if (RegExp(r'特别|番外|预告|花絮|sp|ova', caseSensitive: false).hasMatch(text)) {
    return null;
  }
  final season = RegExp(
    r's(\d+)\s*e(\d+)',
    caseSensitive: false,
  ).firstMatch(text);
  if (season != null) {
    final s = int.tryParse(season[1]!);
    final e = int.tryParse(season[2]!);
    return s == null || e == null ? null : '$s:$e';
  }
  final match = RegExp(
    r'^(?:第|ep?|episode\s*)?\s*(\d+)\s*(?:集|话|期)?$',
    caseSensitive: false,
  ).firstMatch(text.trim());
  if (match != null) {
    final e = int.tryParse(match[1]!);
    return e == null ? null : '1:$e';
  }
  final chinese = RegExp(r'^第([一二三四五六七八九十百零]+)[集话期]$').firstMatch(text.trim());
  if (chinese == null) return null;
  const digits = {
    '零': 0,
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  var total = 0;
  var current = 0;
  for (final char in chinese[1]!.split('')) {
    if (char == '十' || char == '百') {
      total += (current == 0 ? 1 : current) * (char == '十' ? 10 : 100);
      current = 0;
    } else {
      current = digits[char] ?? 0;
    }
  }
  return '1:${total + current}';
}
