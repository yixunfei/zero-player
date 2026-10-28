bool isGenericSourceTitle(String value) => RegExp(
  r'^(welcome(?: to (?:nginx|iis))?!?|nginx|iis windows server|index of /|首页|网站首页)$',
  caseSensitive: false,
).hasMatch(value.trim());
