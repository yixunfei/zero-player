import 'catalog_item.dart';

String normalizedTitle(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s·•:：，,。.!！?？\-—_《》「」]'), '')
    .replaceAll(
      RegExp(
        r'[（(\[](?:1080p|720p|2160p|4k|高清|蓝光)[）)\]]',
        caseSensitive: false,
      ),
      '',
    );

String normalizedYear(String value) =>
    RegExp(r'(?:19|20)\d{2}').firstMatch(value)?.group(0) ?? '';

String workKind(String category) {
  if (RegExp(
    r'动漫|动画|番剧|animation|anime',
    caseSensitive: false,
  ).hasMatch(category)) {
    return 'animation';
  }
  if (RegExp(r'综艺|真人秀|variety', caseSensitive: false).hasMatch(category)) {
    return 'variety';
  }
  if (RegExp(r'电影|片$|movie|film', caseSensitive: false).hasMatch(category)) {
    return 'movie';
  }
  if (RegExp(r'剧|series|drama', caseSensitive: false).hasMatch(category)) {
    return 'series';
  }
  return '';
}

bool _compatibleKind(CatalogItem a, CatalogItem b) =>
    workKind(a.category).isEmpty ||
    workKind(b.category).isEmpty ||
    workKind(a.category) == workKind(b.category);

/// Automatic media substitution requires positive identity evidence, not only
/// a fuzzy title. Unknown years need matching creator metadata.
bool sameDownloadWork(CatalogItem a, CatalogItem b) {
  if (normalizedTitle(a.title) != normalizedTitle(b.title) ||
      !_compatibleKind(a, b) ||
      workVersion(a) != workVersion(b)) {
    return false;
  }
  final ay = normalizedYear(a.year), by = normalizedYear(b.year);
  if (ay.isNotEmpty && by.isNotEmpty) return ay == by;
  if (a.director.trim().isNotEmpty && a.director.trim() == b.director.trim()) {
    return true;
  }
  return false;
}

Map<String, List<CatalogItem>> groupCatalogItems(Iterable<CatalogItem> items) {
  final byTitle = <String, List<CatalogItem>>{};
  for (final item in items) {
    byTitle.putIfAbsent(normalizedTitle(item.title), () => []).add(item);
  }
  final result = <String, List<CatalogItem>>{};
  for (final entry in byTitle.entries) {
    final years = entry.value
        .map((i) => normalizedYear(i.year))
        .where((y) => y.isNotEmpty)
        .toSet();
    final kinds = entry.value
        .map((i) => workKind(i.category))
        .where((k) => k.isNotEmpty)
        .toSet();
    for (final item in entry.value) {
      var year = normalizedYear(item.year);
      var kind = workKind(item.category);
      if (year.isEmpty && years.length == 1) year = years.single;
      if (kind.isEmpty && kinds.length == 1) kind = kinds.single;
      final key = '${entry.key}|$year|$kind|${workVersion(item)}';
      final group = result.putIfAbsent(key, () => []);
      if (!group.any((i) => i.sourceId == item.sourceId && i.id == item.id)) {
        group.add(item);
      }
    }
  }
  return result;
}

String workVersion(CatalogItem item) => RegExp(r'导演剪辑|加长版|未删减|重制版|特别版|剧场版')
    .allMatches('${item.title} ${item.remarks}')
    .map((m) => m.group(0)!)
    .toSet()
    .join('|');
