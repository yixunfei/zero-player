import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/books/data/book_html.dart';
import 'package:zero_player/features/books/domain/book.dart';

/// UU看书 native channel (assets/catalogs/books/verified.json) must expose the
/// same categories, rankings and subcategories as https://www.uukan.org/library.html
/// and parse the shared `.bookbox` list markup used by category, ranking and
/// search pages, while the homepage `#fengtui` recommendations keep working.
BookSource _uukan() {
  final data =
      jsonDecode(File('assets/catalogs/books/verified.json').readAsStringSync())
          as List;
  final record = data.cast<Map>().firstWhere((s) => s['name'] == 'UU看书');
  return BookSource.fromJson(record, builtin: true);
}

String _rule(BookSource source, String key, {required bool discovery}) {
  final discoverKey = 'discover${key[0].toUpperCase()}${key.substring(1)}';
  return (discovery ? source.rules[discoverKey] : null) ??
      source.rules[key] ??
      '';
}

String _row(
  String id,
  String title,
  String author,
  String words,
  String latest,
  int rank,
) =>
    '<div class="bookbox"><div class="p10"><span class="num">$rank</span>'
    '<div class="bookinfo">'
    '<h2 class="bookname"><a href="/book/$id.html">$title</a></h2>'
    '<div class="author">作者：$author</div>'
    '<div class="author">字数：$words</div>'
    '<div class="cat"><span>更新到：</span>'
    '<a href="/chapter/$id/last.html">$latest</a></div>'
    '<div class="update"><span>简介：</span>$title 的简介。</div>'
    '</div></div></div>';

final _listing =
    '<div class="content book"><h1>小说分类 - 玄幻</h1>'
    '${_row('a1', '天渊', '沐潇三生', '638.1万', '第3083章 入塔，登高', 1)}'
    '${_row('a2', '星武纪元', '猪三不', '508.1万', '番外二：定义神明（下）', 2)}'
    '<div class="pages"><div class="pagelink" id="pagelink">'
    '<em id="pagestats">1/100</em><strong>1</strong>'
    '<a href="/library/4UIdwqRRY7YW2MNwYUJqYe/2.html">2</a>'
    '<a href="/library/4UIdwqRRY7YW2MNwYUJqYe/2.html" class="next">&gt;</a>'
    '<a href="/library/4UIdwqRRY7YW2MNwYUJqYe/100.html" class="last">100</a>'
    '</div></div></div>';

const _home =
    '<div class="content-left" id="fengtui" role="main"><h1>热门小说推荐</h1>'
    '<div class="item"><div class="image"><a href="/book/a1.html">'
    '<img src="https://img.cuoceng.com/novel/bookCover/webp/main.webp" '
    'alt="天渊" width="113" height="150" loading="lazy"></a></div>'
    '<dl><dt><a href="/search/沐潇三生.html"><span>沐潇三生</span></a>'
    '<a href="/book/a1.html">天渊</a></dt>'
    '<dd>天渊的简介。</dd></dl></div></div>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = _uukan();

  test('UU看书 catalog mirrors the website categories and rankings', () {
    final categories = source.discoveryCategories;
    expect(categories, hasLength(24));
    expect(categories.first.title, '推荐');
    expect(categories.first.address, '/');
    expect(source.hasDiscovery, isTrue);

    final genres = categories.where((c) => c.group == '分类').toList();
    expect(genres.map((c) => c.title), [
      '玄幻',
      '仙侠',
      '都市',
      '历史',
      '科幻',
      '军事',
      '言情',
      '轻小说',
      '悬疑',
      '奇幻',
      '游戏',
      '诸天无限',
      '武侠',
      '重生',
      '体育',
      '现实',
      '穿越',
      '未删减',
    ]);
    expect(genres.first.address, '/library/4UIdwqRRY7YW2MNwYUJqYe.html');
    expect(genres.every((c) => c.address.startsWith('/library/')), isTrue);

    final ranks = categories.where((c) => c.group == '排行').toList();
    expect(ranks.map((c) => c.title), [
      '读者倾心榜',
      '字耕里程榜',
      '笔耕不辍堂',
      '新玉初藏阁',
      '墨迹未干栏',
    ]);
    expect(ranks.map((c) => c.address), [
      '/ranking/hits.html',
      '/ranking/words.html',
      '/ranking/guru.html',
      '/ranking/create.html',
      '/ranking/update.html',
    ]);
  });

  test('UU看书 category and ranking rows parse fields and paginate', () {
    final document = parseBookHtml(_listing);
    String rule(String key) => _rule(source, key, discovery: true);
    final rows = bookElements(document, rule('list')).toList();
    expect(rows, hasLength(2));
    final row = rows.first;
    expect(bookField(row, rule('title')), '天渊');
    expect(bookField(row, rule('book')), '/book/a1.html');
    expect(
      bookField(row, rule('author')).replaceFirst(RegExp(r'^作者[:：]\s*'), ''),
      '沐潇三生',
    );
    expect(
      bookField(
        row,
        rule('wordCount'),
      ).replaceFirst(RegExp(r'^字数[:：]\s*'), ''),
      '638.1万',
    );
    expect(bookField(row, rule('latest')), '第3083章 入塔，登高');
    expect(bookField(row, rule('rank')), '1');
    expect(bookField(rows[1], rule('rank')), '2');
    expect(
      bookField(document, source.rules['nextDiscover']!),
      '/library/4UIdwqRRY7YW2MNwYUJqYe/2.html',
    );
  });

  test('UU看书 homepage recommendations fall back to the fengtui markup', () {
    final document = parseBookHtml(_home);
    String rule(String key) => _rule(source, key, discovery: true);
    final rows = bookElements(document, rule('list')).toList();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(bookField(row, rule('title')), '天渊');
    expect(bookField(row, rule('book')), '/book/a1.html');
    expect(bookField(row, rule('author')), '沐潇三生');
    expect(bookField(row, rule('description')), '天渊的简介。');
    expect(
      bookField(row, rule('cover')),
      'https://img.cuoceng.com/novel/bookCover/webp/main.webp',
    );
    expect(bookField(row, rule('rank')), isEmpty);
    expect(bookField(document, source.rules['nextDiscover']!), isEmpty);
  });

  test('UU看书 search reuses the base list rules', () {
    final document = parseBookHtml(_listing);
    String rule(String key) => _rule(source, key, discovery: false);
    final rows = bookElements(document, rule('list')).toList();
    expect(rows, hasLength(2));
    expect(bookField(rows.first, rule('title')), '天渊');
    expect(
      bookField(
        rows.first,
        rule('wordCount'),
      ).replaceFirst(RegExp(r'^字数[:：]\s*'), ''),
      '638.1万',
    );
    expect(bookField(rows.first, rule('latest')), '第3083章 入塔，登高');
  });
}