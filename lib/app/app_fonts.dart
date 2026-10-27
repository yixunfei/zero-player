/// Offline font choices shared by preferences, backup validation and themes.
const appFontLabels = {
  'xiaolai': '小赖 · 柔和手写（默认）',
  'notoSans': '思源黑体 / Noto Sans · 清晰简洁',
  'notoSerif': '思源宋体 / Noto Serif · 书卷风格',
  'system': '系统字体',
};

String? appFontFamily(String key) => switch (key) {
  'xiaolai' => 'Xiaolai',
  'notoSans' => 'NotoSansSC',
  'notoSerif' => 'NotoSerifSC',
  _ => null,
};
