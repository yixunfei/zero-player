final class LegadoCategory {
  const LegadoCategory(this.title, this.address);

  final String title, address;

  bool get paginated =>
      RegExp(r'\{\{[^}]*\bpage\b|<[^<>]*,[^<>]*>').hasMatch(address);

  Object toJson() => title.isEmpty ? address : {'title': title, 'url': address};
}

/// The subset of the original source that participates in book and feed requests.
final class LegadoSource {
  LegadoSource.fromJson(Map data)
    : search = _string(data['search'], 64 * 1024),
      library = _string(data['library'], 256 * 1024),
      comment = _string(data['comment'], 64 * 1024),
      categories = _explore(data['explore']),
      enabledExplore = data['enabledExplore'] != false,
      bookUrlPattern = _string(data['bookUrlPattern'], 4096),
      rules = _strings(data['rules'], 48, 64 * 1024),
      headers = _strings(data['headers'], 8, 1024);

  final String search, library, comment, bookUrlPattern;
  final bool enabledExplore;
  final List<LegadoCategory> categories;
  final Map<String, String> rules, headers;

  Iterable<String> get explore =>
      categories.map((category) => category.address);

  Map<String, Object> toJson() => {
    if (search.isNotEmpty) 'search': search,
    if (library.isNotEmpty) 'library': library,
    if (comment.isNotEmpty) 'comment': comment,
    if (categories.isNotEmpty)
      'explore': categories.map((category) => category.toJson()).toList(),
    if (!enabledExplore) 'enabledExplore': false,
    if (bookUrlPattern.isNotEmpty) 'bookUrlPattern': bookUrlPattern,
    'rules': rules,
    if (headers.isNotEmpty) 'headers': headers,
  };

  static String _string(Object? value, int limit) {
    if (value == null) return '';
    if (value is! String || value.length > limit || value.contains('\x00')) {
      throw const FormatException('Legado 规则超过大小限制或格式无效');
    }
    return value.trim();
  }

  static List<LegadoCategory> _explore(Object? input) {
    if (input == null) return const [];
    if (input is! List || input.length > 512) {
      throw const FormatException('Legado 发现分类数量无效');
    }
    return List.unmodifiable(
      input.map((item) {
        if (item is Map) {
          return LegadoCategory(
            _string(item['title'], 160),
            _string(item['url'], 64 * 1024),
          );
        }
        return LegadoCategory('', _string(item, 64 * 1024));
      }),
    );
  }

  static Map<String, String> _strings(Object? raw, int count, int length) {
    if (raw == null) return const {};
    if (raw is! Map ||
        raw.length > count ||
        raw.keys.any((key) => key is! String)) {
      throw const FormatException('Legado 规则集合无效');
    }
    return Map.unmodifiable({
      for (final entry in raw.entries)
        entry.key as String: _string(entry.value, length),
    });
  }
}
