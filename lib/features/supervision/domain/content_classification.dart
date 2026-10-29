/// Normalize publisher labels and user keywords without executing expressions.
String normalizeContent(String input) {
  const traditional = {
    '倫': '伦',
    '裏': '里',
    '無': '无',
    '碼': '码',
    '視': '视',
    '頻': '频',
    '區': '区',
    '國': '国',
    '產': '产',
    '愛': '爱',
    '慾': '欲',
    '劇': '剧',
    '級': '级',
    '寫': '写',
    '真': '真',
    '門': '门',
    '專': '专',
    '體': '体',
    '覽': '览',
  };
  final folded = String.fromCharCodes(
    input.runes.map((r) => r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : r),
  ).toLowerCase();
  return folded
      .split('')
      .map((c) => traditional[c] ?? c)
      .join()
      .replaceAll(RegExp(r'[^a-z0-9㐀-鿿]'), '');
}

final _adultLabels = <String>{
  '成人',
  'adult',
  'erotic',
  'erotica',
  'sex',
  '成人专区',
  '伦理片',
  '伦理',
  '伦理剧',
  '理论片',
  '情色',
  '色情',
  '三级',
  '三级片',
  '日本av',
  '欧美av',
  'av',
  'xxx',
  '无码',
  '有码',
  '里番',
  '18禁',
  '十八禁',
  'r18',
  'r18g',
  '19禁',
  'hentai',
  'porn',
  'pornhub',
  '91porn',
  'javbus',
  'javdb',
  'javlibrary',
  'xnxx',
  'redtube',
  'youporn',
  'nsfw',
};
final _adultMarkers = <String>[
  '色情',
  '情色',
  '伦理片',
  '成人影片',
  '成人视频',
  '成人电影',
  '成人影院',
  '成人网站',
  '成人频道',
  '成人专区',
  '三级片',
  '三级伦理',
  '无码',
  '有码av',
  '里番',
  '十八禁',
  '麻豆传媒',
  '天美传媒',
  'av女优',
  '无修正',
  '淫乱',
  '乱伦',
  '性爱',
  '自慰',
  'pornhub',
  '91porn',
  'javbus',
  'javdb',
  'javlibrary',
  'xnxx',
  'redtube',
  'youporn',
  'xvideos',
  'xhamster',
  'hentai',
  'nsfw',
];
final _adultWords = RegExp(
  r'(^|[^a-z0-9])(av|xxx|r[ -]?18g?|porn(?:ography)?|hentai|nsfw)(?=$|[^a-z0-9])|18\s*\+|18\s*禁',
  caseSensitive: false,
);
final _regionalAdultLabel = RegExp(
  r'^(?:日本|韩国|日韩|欧美|港台|香港|台湾|国产|中国|西方)?(?:伦理|理论|三级)(?:片|剧|电影)?$',
);

bool adultContent(String text, {bool category = false}) {
  final normalized = normalizeContent(text);
  final folded = String.fromCharCodes(
    text.runes.map((r) => r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : r),
  ).replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]'), '');
  if (_adultMarkers.any(normalized.contains) || _adultWords.hasMatch(folded)) {
    return true;
  }
  if (_adultLabels.contains(normalized)) return true;
  if (category && _regionalAdultLabel.hasMatch(normalized)) {
    return true;
  }
  return category &&
      folded.split(RegExp(r'[,，/|、;；\s]+')).any((part) {
        final label = normalizeContent(part);
        return _adultLabels.contains(label) ||
            _regionalAdultLabel.hasMatch(label);
      });
}
