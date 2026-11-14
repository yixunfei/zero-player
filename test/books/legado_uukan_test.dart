import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/features/books/data/book_import.dart';
import 'package:zero_player/features/books/data/legado/legado_worker.dart';
import 'package:zero_player/features/books/domain/book.dart';

/// UU看书 (https://www.uukan.org) is a representative Legado channel: path-based
/// category and chapter pagination, list rows whose author and word count share
/// the `.author` class, and a detail page whose cover selector also matches the
/// related-book sidebar. These samples mirror that markup so the compatible
/// parsing and display rules stay verified.
BookSource _uukan() => parseBookSourceRecord({
  'bookSourceName': 'UU看书',
  'bookSourceUrl': 'https://www.uukan.org',
  'bookSourceType': 0,
  'enabledExplore': true,
  'exploreUrl':
      '玄幻::/library/4UIdwqRRY7YW2MNwYUJqYe.html\n'
      '仙侠::/library/1VFsPoIVRJXnEcEGknQVQ2.html\n'
      '都市::/library/2bD14zoJ5n5YWC79VN8jh8.html',
  'searchUrl': '/search/{{key}}.html',
  'ruleSearch': _listRules(),
  'ruleExplore': {..._listRules(), 'nextExploreUrl': '.pagelink a.next@href'},
  'ruleBookInfo': {
    'name': '.booktitle@text',
    'author': '.booktag a.red@text',
    'kind': '.booktag a.blue@text',
    'wordCount': '.booktag span.blue.0@text',
    'lastChapter': '.bookchapter@text',
    'updateTime': '.booktime@text##更新时间：',
    'intro': '.bookintro@text',
    'coverUrl': '.thumbnail@src',
  },
  'ruleToc': {
    'chapterList': '#allchapter dd a',
    'chapterName': 'text',
    'chapterUrl': 'href',
    'nextTocUrl': '#linkNext@href',
  },
  'ruleContent': {'content': '#content@text'},
});

Map<String, String> _listRules() => {
  'bookList': '.bookbox',
  'name': '.bookname a@text',
  'bookUrl': '.bookname a@href',
  'author': '.author.0@text##作者：',
  'wordCount': '.author.1@text##字数：',
  'lastChapter': '.cat a@text',
  'intro': '.update@text##简介：',
};

String _row(
  String id,
  String title,
  String author,
  String words,
  String latest,
) =>
    '<div class="bookbox"><div class="p10"><div class="bookinfo">'
    '<h2 class="bookname"><a href="/book/$id.html">$title</a></h2>'
    '<div class="author">作者：$author</div>'
    '<div class="author">字数：$words</div>'
    '<div class="cat"><span>更新到：</span>'
    '<a href="/chapter/$id/last.html">$latest</a></div>'
    '<div class="update"><span>简介：</span>$title 的简介。</div>'
    '</div></div></div>';

final _listing =
    '<div class="content book"><h1>小说分类 - 玄幻</h1>'
    '${_row('a1', '天渊', '沐潇三生', '638.1万', '第3083章 入塔，登高')}'
    '${_row('a2', '星武纪元', '猪三不', '508.1万', '番外二：定义神明（下）')}'
    '<div class="pages"><div class="pagelink">'
    '<strong>1</strong><a href="/library/4UIdwqRRY7YW2MNwYUJqYe/2.html">2</a>'
    '<a href="/library/4UIdwqRRY7YW2MNwYUJqYe/2.html" class="next">&gt;</a>'
    '</div></div></div>';

const _cover = 'https://img.cuoceng.com/novel/bookCover/webp/main.webp';
const _detail =
    '<div class="bookinfo"><h1 class="booktitle">天渊</h1>'
    '<p class="booktag">'
    '<a href="/search/沐潇三生.html" class="red">沐潇三生</a>'
    '<a href="/library/4UIdwqRRY7YW2MNwYUJqYe.html" class="blue">玄幻</a>'
    '<span class="blue">638.1万字</span>'
    '<span class="blue">5341.3万阅读</span>'
    '<span class="red">连载中</span></p>'
    '<p class="bookintro">百年前，陈青源进入了一个名为天渊的禁区。</p>'
    '<p>最新章节：<a class="bookchapter" href="/chapter/a1/last.html">'
    '第3083章 入塔，登高</a></p>'
    '<p class="booktime">更新时间：2026-11-13 20:24:11</p></div>'
    '<img class="thumbnail" alt="天渊" src="$_cover">'
    '<img class="thumbnail" alt="相关书" src="https://img.cuoceng.com/related.webp">';

const _toc =
    '<div class="book chapterlist"><h1>天渊章节列表</h1><div id="allchapter"><dl>'
    '<dd data-num="1"><a href="/chapter/a1/c1.html">第1章 从天渊禁区归来</a></dd>'
    '<dd data-num="2"><a href="/chapter/a1/c2.html">第2章 悔婚</a></dd>'
    '</dl></div></div>'
    '<a class="btn btn-default" href="/chapter/a1/2.html" id="linkNext">下一页</a>';

const _content =
    '<div id="content" class="readcontent">'
    '<p>“陈青源，我给你两个选择。”</p><p>一处名为天渊的禁区深处。</p></div>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = _uukan();
  final token = CancellationToken();

  test('UU看书 categories keep every grouped entry', () {
    expect(source.legado!.categories.map((item) => item.title), [
      '玄幻',
      '仙侠',
      '都市',
    ]);
    expect(source.hasDiscovery, isTrue);
    expect(source.hasSearch, isTrue);
  });

  _pageTests(source, token);
}

void _pageTests(BookSource source, CancellationToken token) {
  test(
    'UU看书 list rows split shared author/word-count classes and paginate',
    () async {
      final page = await runLegadoJob(
        LegadoJob(
          source,
          Uri.parse(
            'https://www.uukan.org/library/4UIdwqRRY7YW2MNwYUJqYe.html',
          ),
          LegadoOperation.books,
          discovery: true,
          input: _listing,
        ),
        token,
      );
      expect(page.books, hasLength(2));
      final book = page.books.first;
      expect(book.title, '天渊');
      expect(book.author, '沐潇三生');
      expect(book.wordCount, '638.1万');
      expect(book.latestChapter, '第3083章 入塔，登高');
      expect(book.uri.path, '/book/a1.html');
      expect(page.links, ['/library/4UIdwqRRY7YW2MNwYUJqYe/2.html']);
    },
  );

  test('UU看书 detail exposes genre/word-count and a single cover URL', () async {
    final page = await runLegadoJob(
      LegadoJob(
        source,
        Uri.parse('https://www.uukan.org/book/a1.html'),
        LegadoOperation.details,
        input: _detail,
      ),
      token,
    );
    final book = page.books.single;
    expect(book.title, '天渊');
    expect(book.author, '沐潇三生');
    expect(book.category, '玄幻');
    expect(book.wordCount, '638.1万字');
    expect(book.latestChapter, '第3083章 入塔，登高');
    expect(book.updatedLabel, '2026-11-13 20:24:11');
    expect(book.cover, _cover);
    expect(book.cover, isNot(contains('%0A')));
    expect(book.cover, isNot(contains('related')));
  });

  test('UU看书 chapter list paginates through the next-page link', () async {
    final book = Book(
      source.id,
      BookKind.text,
      '天渊',
      '沐潇三生',
      Uri.parse('https://www.uukan.org/book/a1.html'),
    );
    final page = await runLegadoJob(
      LegadoJob(
        source,
        Uri.parse('https://www.uukan.org/chapter/a1.html'),
        LegadoOperation.toc,
        input: _toc,
        book: book,
      ),
      token,
    );
    expect(page.chapters.map((item) => item.title), ['第1章 从天渊禁区归来', '第2章 悔婚']);
    expect(page.links, ['/chapter/a1/2.html']);
  });

  test('UU看书 search reuses the list rules and content is extracted', () async {
    final search = await runLegadoJob(
      LegadoJob(
        source,
        Uri.parse('https://www.uukan.org/search/天渊.html'),
        LegadoOperation.books,
        query: '天渊',
        input: _listing,
      ),
      token,
    );
    expect(search.books.first.title, '天渊');
    final body = await runLegadoJob(
      LegadoJob(
        source,
        Uri.parse('https://www.uukan.org/chapter/a1/c1.html'),
        LegadoOperation.content,
        input: _content,
      ),
      token,
    );
    expect(body.content, contains('陈青源'));
    expect(body.content, contains('天渊的禁区深处'));
  });
}
