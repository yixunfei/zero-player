const _cctvTitles = {
  '1': '综合',
  '2': '财经',
  '3': '综艺',
  '4': '中文国际',
  '5': '体育',
  '5+': '体育赛事',
  '6': '电影',
  '7': '国防军事',
  '8': '电视剧',
  '9': '纪录',
  '10': '科教',
  '11': '戏曲',
  '12': '社会与法',
  '13': '新闻',
  '14': '少儿',
  '15': '音乐',
  '16': '奥林匹克',
  '17': '农业农村',
};

/// Match known programme aliases, keeping region feeds and UHD channels distinct.
String? cctvIdentity(String name) {
  final compact = name
      .toUpperCase()
      .replaceAll('＋', '+')
      .replaceFirst(
        RegExp(r'^\s*[（(\[]\s*(?:SD|HD|标清|高清|720P|1080P)\s*[）)\]]\s*'),
        '',
      )
      .replaceAll(RegExp(r'[\s_\-（）()]'), '')
      .replaceAll(RegExp(r'(?:超高清|高清|标清|HD|SD|1080P|720P)+$'), '');
  final match = RegExp(
    r'^(?:CCTV|央视|中央)(\d{1,2})(\+|PLUS)?(.*)$',
  ).firstMatch(compact);
  if (match == null) return null;
  final number = int.parse(match[1]!).toString();
  final suffix = match[3]!;
  final key = '$number${match[2] != null ? '+' : ''}';
  if (!_cctvTitles.containsKey(key)) return null;
  final aliases = {'', _cctvTitles[key], '台'};
  if (key == '7') aliases.addAll({'军事农业', '军事'});
  if (key == '9') aliases.add('记录');
  return aliases.contains(suffix) ? 'CCTV$key' : null;
}

String channelIdentity(String name) =>
    cctvIdentity(name) ??
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String channelDisplayName(String name) {
  final identity = cctvIdentity(name);
  if (identity == null) return name;
  final key = identity.substring(4);
  return 'CCTV-$key ${_cctvTitles[key]}';
}

bool channelMatchesQuery(String name, String query) {
  final term = query.trim().toLowerCase();
  return name.toLowerCase().contains(term) ||
      (cctvIdentity(name) != null &&
          channelIdentity(
            name,
          ).toLowerCase().contains(term.replaceAll(RegExp(r'[\s\-]'), '')));
}
