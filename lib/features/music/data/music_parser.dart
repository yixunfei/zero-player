import 'package:html/parser.dart' as html;
import '../../../core/network/network_target_policy.dart';
import '../domain/music_track.dart';

MusicSearchResult parseMusicSearch(
  String body, {
  required String query,
  required int page,
  DateTime? fetchedAt,
}) {
  final document = html.parse(body);
  final rows = document.querySelectorAll('.playlist .track');
  if (rows.isEmpty && document.querySelector('.search-empty-state') == null) {
    throw const FormatException('音乐渠道页面已变更或暂时不可用，请稍后重试');
  }
  final tracks = <MusicTrack>[];
  final seen = <String>{};
  for (final row in rows.take(200)) {
    final owner = row.attributes['data-owner-id'] ?? '';
    final remote = row.attributes['data-track-id'] ?? '';
    final title = row.querySelector('.track-title')?.text.trim() ?? '';
    final artist =
        row
            .querySelector('.track-artist')
            ?.text
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim() ??
        '';
    if (!RegExp(r'^-?\d+$').hasMatch(owner) ||
        !RegExp(r'^\d+$').hasMatch(remote) ||
        title.isEmpty) {
      continue;
    }
    final id = '${owner}_$remote';
    final raw = row.attributes['data-download'] ?? '';
    try {
      var url = Uri.parse(raw);
      NetworkTargetPolicy.validateUri(url);
      const NetworkTargetPolicy().validateAccess(url, originalOrigin: false);
      // The site's own player repairs this legacy CDN spelling as well.
      if (url.host.endsWith('v4s1.myfreemp3.ink')) {
        url = url.replace(
          host: url.host.replaceFirst(
            RegExp(r'v4s1\.myfreemp3\.ink$'),
            'v4.s1.myfreemp3.ink',
          ),
        );
      }
      if (!seen.add(id)) continue;
      final time = row.querySelector('.track-duration')?.text.trim() ?? '';
      final parts = time.split(':').map((p) => int.tryParse(p) ?? 0).toList();
      var seconds = 0;
      for (final part in parts) {
        seconds = seconds * 60 + part;
      }
      tracks.add(
        MusicTrack(
          id: id,
          title: title.replaceAll(RegExp(r'\s+'), ' '),
          artist: artist,
          url: url,
          duration: Duration(seconds: seconds.clamp(0, 86400)),
          query: query,
          page: page,
          fetchedAt: fetchedAt ?? DateTime.now(),
        ),
      );
    } on FormatException {
      // One malformed or unsafe row must not discard other valid songs.
    }
  }
  if (rows.isNotEmpty && tracks.isEmpty) {
    throw const FormatException('音乐渠道没有返回可用的歌曲地址');
  }
  final hasNext = document.querySelectorAll('.list-pagination a[href]').any((
    a,
  ) {
    final uri = Uri.tryParse(a.attributes['href']!);
    return int.tryParse(uri?.queryParameters['page'] ?? '') == page + 1;
  });
  return MusicSearchResult(List.unmodifiable(tracks), hasNext: hasNext);
}
