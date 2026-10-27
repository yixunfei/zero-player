import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/discovery/data/recommendation_repository.dart';
import 'package:zero_player/features/live/data/m3u_parser.dart';

void main() {
  test('weekly rankings accept rating and ignore missing titles', () {
    final items = parseRecommendations('hot', {
      'data': [
        {
          'title': 'Example',
          'rating': 8.8,
          'cover': 'https://example.org/a.jpg',
        },
        {'rating': 4},
      ],
    });
    expect(items.single.title, 'Example');
    expect(items.single.subtitle, '8.8');
  });
  test('calendar filters weekday and falls back to original title', () {
    final items = parseRecommendations('bangumi', [
      {
        'weekday': {'id': 1, 'cn': '星期一'},
        'items': [
          {'name_cn': '', 'name': 'A'},
        ],
      },
      {
        'weekday': {'id': 2},
        'items': [
          {'name': 'B'},
        ],
      },
    ], type: '1');
    expect(items.single.title, 'A');
    expect(items.single.subtitle, '星期一');
  });
  test('M3U round trip preserves alternate URLs and required headers', () {
    final base = Uri.parse('https://example.org/list.m3u');
    final original = parseM3u(
      '#EXTM3U\n#EXTINF:-1 tvg-id="a" group-title="G",A\n'
          '#EXTVLCOPT:http-user-agent=Player\n#EXTVLCOPT:http-referrer=https://example.org/\n'
          'a.m3u8\nb.m3u8\n',
      base,
      'list',
    );
    final restored = parseM3u(exportM3u(original), base, 'list');
    expect(restored.single.urls, original.single.urls);
    expect(restored.single.headers, original.single.headers);
  });
}
