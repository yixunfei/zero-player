import 'content_classification.dart';

/// Publisher-level evidence, never a blacklist of ambiguous display names.
/// slapibf.com: category API reviewed 2026-10-28 (explicit adult taxonomy).
/// shayuapi.com: bundled MaccmsResources/R18.json. See the acceptance report.
const _adultHosts = {'slapibf.com', 'shayuapi.com'};

bool knownAdultHost(String host) {
  final normalized = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  return _adultHosts.any(
    (adult) => normalized == adult || normalized.endsWith('.$adult'),
  );
}

/// A mixed mainstream catalog keeps item-level filtering. An adult-only
/// taxonomy requires multiple distinct labels, not a single ethics category.
bool adultCatalog(Iterable<String> categories) {
  final labels = categories
      .map(normalizeContent)
      .where((s) => s.isNotEmpty)
      .toSet();
  const mainstream = {
    '电影',
    '电视剧',
    '连续剧',
    '综艺',
    '动漫',
    '动画片',
    '纪录片',
    '短剧',
    '新闻',
    '体育',
    '动作片',
    '喜剧片',
    '爱情片',
    '科幻片',
    '恐怖片',
    '剧情片',
    '战争片',
    '国产剧',
    '欧美剧',
    '日韩剧',
  };
  if (labels.any(mainstream.contains)) return false;
  return labels.where((label) => adultContent(label, category: true)).length >=
      3;
}
