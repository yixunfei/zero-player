import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/book_import.dart';
import 'package:zero_player/features/books/data/book_source_links.dart';
import 'package:zero_player/features/books/data/legado/legado_request.dart';
import 'package:zero_player/features/books/data/legado/legado_worker.dart';
import 'package:zero_player/features/books/domain/book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Legado import URLs preserve nested query strings and normalize links',
    () {
      const link = 'https://example.test/source.json?type=book&name=%E4%B9%A6';
      expect(
        bookSourceLink(
          'legado://import/bookSource?src=${Uri.encodeComponent(link)}',
        ).toString(),
        link,
      );
      expect(
        bookSourceLink('yuedu://booksource/importonline?src=$link').toString(),
        link,
      );
      expect(
        bookSourceLink(
          'https://github.com/publisher/repo/blob/main/source.json',
        ).toString(),
        'https://raw.githubusercontent.com/publisher/repo/main/source.json',
      );
      expect(
        bookSubscriptionId(
          bookSourceLink(
            'https://www.yckceo.com/yuedu/shuyuan/content/id/8.html',
          ),
        ),
        bookSubscriptionId(
          bookSourceLink('https://www.yckceo.com/yuedu/shuyuan/json/id/8.json'),
        ),
      );
      expect(
        () => bookSourceLink('legado://import/theme?src=$link'),
        throwsFormatException,
      );
      expect(
        () => bookSourceLink(
          'legado://import/bookSource?src=http://127.0.0.1/books',
        ),
        throwsFormatException,
      );
    },
  );

  test('v2 export normalizes HTTP URLs, search tokens and chapter rules', () {
    final parsed = parseBookSources(
      '\uFEFF${jsonEncode({
        'bookSources': [
          {'bookSourceName': '旧版书源', 'bookSourceUrl': 'http://legacy.test', 'ruleSearchUrl': 'http://legacy.test/search@keyword=searchKey&page=_searchPage', 'ruleSearchList': 'class.result', 'ruleSearchName': 'h3@text#^书名：', 'ruleSearchNoteUrl': 'a@href', 'ruleChapterList': 'id.index@tag.a', 'ruleChapterName': 'text', 'ruleContentUrl': 'href', 'ruleBookContent': 'id.content@html'},
        ],
      })}',
    );
    expect(parsed.rejected, 0);
    final source = parsed.sources.single;
    final request = LegadoRequest.parse(
      source,
      source.endpoint,
      source.legado!.search,
      key: '金庸',
      page: 3,
    );
    expect(request.uri.toString(), 'https://legacy.test/search');
    expect(request.form, {'keyword': '金庸', 'page': '3'});
    expect(source.legado!.rules['searchTitle'], 'h3@text##^书名：');
    expect(
      () => source.requestTarget(Uri.parse('http://legacy.test/book')),
      throwsFormatException,
    );
  });

  _rules();
  _requestIdentity();
  _discoveryBoundary();
  _refresh();
}

void _discoveryBoundary() {
  test('grouped discovery preserves every result and the next request', () async {
    final source = parseBookSourceRecord({
      'bookSourceName': '榜单样本',
      'bookSourceUrl': 'https://example.test',
      'exploreUrl': [
        {'title': '榜单', 'url': ''},
        {
          'title': '月票',
          'url':
              r'/api/rank,{"method":"POST","body":{"offset":"{{(page-1)*20}}"}}',
        },
        {'title': '分类', 'url': ''},
        {'title': '科幻', 'url': '/science'},
      ],
      'ruleExplore': {
        'bookList': r'$.books[*]',
        'name': r'$.title',
        'bookUrl': r'$.url',
        'rank': r'$.rank',
        'wordCount': r'$.size',
        'updateTime': r'$.update',
        'nextPageUrl': r'$.next',
      },
      'ruleContent': {'content': '.content@text'},
    });
    final categories = source.legado!.categories;
    expect(categories.map((item) => (item.group, item.title)), [
      ('榜单', '月票'),
      ('分类', '科幻'),
    ]);
    final request = LegadoRequest.parse(
      source,
      source.endpoint,
      categories.first.address,
      page: 2,
    );
    expect(request.uri.path, '/api/rank');
    expect(request.json, {'offset': '20'});
    final books = [
      for (var i = 0; i < 137; i++)
        {
          'title': '书目 $i',
          'url': '/book/$i',
          'rank': '$i',
          if (i == 1) 'size': '80万字',
          if (i == 1) 'update': '昨天',
        },
    ];
    final result = await runLegadoJob(
      LegadoJob(
        source,
        request.uri,
        LegadoOperation.books,
        discovery: true,
        input: jsonEncode({
          'books': [...books, books.first],
          'next': '/api/rank?cursor=4',
        }),
      ),
      CancellationToken(),
    );
    expect(result.books, hasLength(137));
    expect(result.books[1].rankLabel, '1');
    expect(result.books[1].wordCount, '80万字');
    expect(result.books[1].updatedLabel, '昨天');
    expect(result.books.last.wordCount, isEmpty);
    expect(result.links, ['/api/rank?cursor=4']);
    await expectLater(
      runLegadoJob(
        LegadoJob(
          source,
          source.endpoint,
          LegadoOperation.content,
          input: '<div class="content"><img src="/page.jpg"></div>',
        ),
        CancellationToken(),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('仅提供图片'),
        ),
      ),
    );
  });
}

void _requestIdentity() {
  test(
    'same endpoint keeps books and chapters with different POST bodies',
    () async {
      final source = parseBookSourceRecord({
        'bookSourceName': 'POST 目录',
        'bookSourceUrl': 'https://post.test',
        'searchUrl': '/search',
        'ruleSearch': {
          'bookList': r'$[*]',
          'name': r'$.title',
          'bookUrl': r'/book,{"method":"POST","body":{"id":"{{$.id}}"}}',
        },
        'ruleToc': {
          'chapterList': r'$[*]',
          'chapterName': r'$.title',
          'chapterUrl': r'/chapter,{"method":"POST","body":{"id":"{{$.id}}"}}',
        },
        'ruleContent': {'content': r'$.body'},
      });
      final token = CancellationToken();
      const input = '[{"id":1,"title":"甲"},{"id":2,"title":"乙"}]';
      final list = await runLegadoJob(
        LegadoJob(source, source.endpoint, LegadoOperation.books, input: input),
        token,
      );
      expect(list.books.map((book) => book.id).toSet(), hasLength(2));
      final book = list.books.first;
      final toc = await runLegadoJob(
        LegadoJob(
          source,
          book.uri,
          LegadoOperation.toc,
          input: input,
          book: book,
        ),
        token,
      );
      expect(toc.chapters.map((chapter) => chapter.id).toSet(), hasLength(2));
      for (final chapter in toc.chapters) {
        final saved = BookChapter.fromJson(chapter.toJson());
        expect(saved.id, chapter.id);
        expect(LegadoRequest.parse(source, saved.uri, saved.request).json, {
          'id': chapter.title == '甲' ? '1' : '2',
        });
      }
    },
  );
}

void _rules() {
  test(
    'structured rules parse JSON search, XPath chapters and cleaned content',
    () async {
      final source = _source();
      final token = CancellationToken();
      final search = await runLegadoJob(
        LegadoJob(
          source,
          source.endpoint,
          LegadoOperation.books,
          input: '{"data":{"items":[{"id":7,"title":"样本书","author":"作者：甲"}]}}',
        ),
        token,
      );
      final book = search.books.single;
      expect(book.title, '样本书');
      expect(book.author, '甲');
      expect(book.uri.path, '/book/7');
      final catalog = await runLegadoJob(
        LegadoJob(
          source,
          book.uri,
          LegadoOperation.toc,
          book: book,
          input: '<ol id="toc"><li><a href="/chapter/1">第一章</a></li></ol>',
        ),
        token,
      );
      final chapter = catalog.chapters.single;
      expect(chapter.title, '第一章');
      final body = await runLegadoJob(
        LegadoJob(
          source,
          chapter.uri,
          LegadoOperation.content,
          book: book,
          chapter: chapter,
          input:
              '<article><p>甲 广告123</p><p>乙</p><script>hidden()</script></article>',
        ),
        token,
      );
      expect(body.content, '甲\n\n乙');
    },
  );

  test(
    'Legado RSS source uses article rules and can resolve direct audio',
    () async {
      expect(
        () => parseBookSourceRecord({
          'sourceName': '视频',
          'sourceUrl': 'https://video.test/index',
          'type': 2,
        }),
        throwsFormatException,
      );
      final source = parseBookSourceRecord({
        'sourceName': '播客',
        'sourceUrl': 'https://podcast.test/index',
        'kind': 'audio',
        'ruleArticles': r'$.episodes[*]',
        'ruleTitle': r'$.title',
        'ruleLink': r'$.audio',
        'mediaHosts': ['audio.test'],
      });
      final entries = await runLegadoJob(
        LegadoJob(
          source,
          source.endpoint,
          LegadoOperation.articles,
          input:
              '{"episodes":[{"title":"第一集","audio":"https://audio.test/1.mp3"},'
              '{"title":"外域","audio":"https://unlisted.test/2.mp3"}]}',
        ),
        CancellationToken(),
      );
      expect(entries.chapters.map((part) => part.title), ['第一集']);
      expect(entries.chapters.single.uri.host, 'audio.test');
    },
  );
}

void _refresh() {
  test('refresh keeps source identity and local preferences', () async {
    final directory = await Directory.systemTemp.createTemp(
      'legado-subscription-',
    );
    final services = AppServices.scoped(directory, AppDatabase.memory());
    addTearDown(() async {
      await services.close();
      await directory.delete(recursive: true);
    });
    await services.settings.load();
    await services.supervision.load();
    final repository = services.books;
    final subscription = Uri.parse('https://publisher.test/books.json');
    final original = _source();
    final added = await repository.importSources([
      original,
    ], subscription: subscription);
    expect(added.added, 1);
    await repository.saveSource(original, {
      'enabled': true,
      'favorite': true,
      'group': '我的分组',
    });
    final newSource = _source(name: '新版名称');
    expect(newSource.id, original.id);
    final updated = await repository.importSources([
      newSource,
    ], subscription: subscription);
    expect(updated.updated, 1);
    await repository.saveSource(original, {'favorite': true});
    final entry = (await repository.sources(
      BookKind.text,
    )).singleWhere((entry) => entry.source.id == original.id);
    expect(entry.source.name, '新版名称');
    expect(entry.enabled, isTrue);
    expect(entry.favorite, isTrue);
    expect(entry.group, '我的分组');
    final saved = (await repository.subscriptions()).single;
    expect(saved.count, 1);
    await repository.removeSubscription(saved);
    expect(await repository.subscriptions(), isEmpty);
    expect(
      (await repository.sources(
        BookKind.text,
      )).any((entry) => entry.source.id == original.id),
      isTrue,
    );
  });
}

BookSource _source({String name = '示例'}) => parseBookSourceRecord({
  'bookSourceName': name,
  'bookSourceUrl': 'https://book.test/',
  'searchUrl': '/search?key={{key}}',
  'ruleSearch': {
    'bookList': r'$.data.items[*]',
    'name': r'$.title',
    'author': r'$.author##^作者：',
    'bookUrl': r'/book/{{$.id}}',
  },
  'ruleToc': {
    'chapterList': '@XPath://ol[@id="toc"]/li/a',
    'chapterName': 'text',
    'chapterUrl': 'href',
  },
  'ruleContent': {
    'content': '@XPath://article/p/text()',
    'replaceRegex': r'## 广告\d+',
  },
});
