/// Only explicit publisher XMLTV URLs are accepted; no guessed programme data.
Uri? playlistEpg(String text, Uri base) {
  final header = text
      .replaceFirst('\uFEFF', '')
      .trimLeft()
      .split(RegExp(r'\r?\n'))
      .first;
  if (!header.startsWith('#EXTM3U')) return null;
  final match = RegExp(
    r'''(?:x-tvg-url|url-tvg|tvg-url)\s*=\s*["']([^"']*)["']''',
    caseSensitive: false,
  ).firstMatch(header);
  for (final value in (match?[1] ?? '').split(',')) {
    if (value.trim().isEmpty) continue;
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null) continue;
    final uri = base.resolveUri(parsed);
    if ({'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty) {
      return uri;
    }
  }
  return null;
}
