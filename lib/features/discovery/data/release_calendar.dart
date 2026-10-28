import 'dart:convert';
import 'package:html/parser.dart' as html;
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/persistence/app_database.dart';
import '../../../core/text/display_text.dart';

final releaseCalendarUri = Uri.parse('https://movie.douban.com/coming');

final class FilmRelease {
  const FilmRelease(this.title, this.date, this.genres, this.region, this.url);
  final String title, date, genres, region;
  final Uri url;
  Map<String, String> toJson() => {
    'title': title,
    'date': date,
    'genres': genres,
    'region': region,
    'url': url.toString(),
  };
}

List<FilmRelease> parseReleaseCalendar(String text) {
  final document = html.parse(text);
  final found = <String, FilmRelease>{};
  for (final row in document.querySelectorAll('table.coming_list tbody tr')) {
    final cells = row.querySelectorAll('td');
    if (cells.length < 4) continue;
    final link = cells[1].querySelector('a[href]');
    final url = Uri.tryParse(link?.attributes['href'] ?? '');
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'movie.douban.com' ||
        !RegExp(r'^/subject/\d+/$').hasMatch(url.path) ||
        url.userInfo.isNotEmpty) {
      continue;
    }
    final title = displayText(link?.text ?? '');
    final date = displayText(cells[0].text);
    if (title.isEmpty ||
        !RegExp(r'^(?:\d{4}年)?\d{1,2}月(?:\d{1,2}日)?$').hasMatch(date)) {
      continue;
    }
    found[url.toString()] = FilmRelease(
      title,
      date,
      displayText(cells[2].text),
      displayText(cells[3].text),
      url,
    );
    if (found.length >= 100) break;
  }
  if (found.isEmpty) throw const FormatException('上映日历未返回有效条目');
  return found.values.toList();
}

final class ReleaseCalendar {
  const ReleaseCalendar(this.items, this.updatedAt, {this.cached = false});
  final List<FilmRelease> items;
  final DateTime updatedAt;
  final bool cached;
}

final class ReleaseCalendarRepository {
  ReleaseCalendarRepository(this.network, this.db, {Uri? endpoint})
    : endpoint = endpoint ?? releaseCalendarUri;
  final DocumentClient network;
  final AppDatabase db;
  final Uri endpoint;
  static const _key = 'release-calendar:douban';
  Future<ReleaseCalendar> load({
    bool refresh = false,
    required CancellationToken cancellation,
  }) async {
    final cached = await _cached();
    cancellation.check();
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.updatedAt) <
            const Duration(hours: 6)) {
      return cached;
    }
    try {
      final response = await network.get(
        endpoint,
        cancellation: cancellation,
        maxBytes: 1024 * 1024,
        networkTimeout: const Duration(seconds: 12),
      );
      final items = parseReleaseCalendar(response.text);
      cancellation.check();
      final updated = DateTime.now();
      await db
          .write('INSERT OR REPLACE INTO recommendation_cache VALUES(?,?,?)', [
            _key,
            jsonEncode(items.map((item) => item.toJson()).toList()),
            updated.millisecondsSinceEpoch,
          ]);
      return ReleaseCalendar(items, updated);
    } catch (_) {
      cancellation.check();
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<ReleaseCalendar?> _cached() async {
    final rows = await db.rows(
      'SELECT payload,updated_at FROM recommendation_cache WHERE provider=?',
      [_key],
    );
    if (rows.isEmpty) return null;
    try {
      final items = (jsonDecode(rows.single['payload'] as String) as List)
          .map((row) {
            final data = row as Map;
            final url = Uri.parse(data['url'] as String);
            if (url.scheme != 'https' ||
                url.host != 'movie.douban.com' ||
                url.userInfo.isNotEmpty) {
              throw const FormatException('无效来源链接');
            }
            return FilmRelease(
              data['title'] as String,
              data['date'] as String,
              data['genres'] as String,
              data['region'] as String,
              url,
            );
          })
          .take(100)
          .toList();
      if (items.isEmpty) return null;
      return ReleaseCalendar(
        items,
        DateTime.fromMillisecondsSinceEpoch(rows.single['updated_at'] as int),
        cached: true,
      );
    } catch (_) {
      return null;
    }
  }
}
