import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/audiobook_files.dart';
import 'package:zero_player/features/books/data/book_html.dart';
import 'package:zero_player/features/books/data/book_import.dart';
import 'package:zero_player/features/books/data/book_store.dart';
import 'package:zero_player/features/books/data/legado/legado_request.dart';
import 'package:zero_player/features/books/data/legado/legado_rules.dart';
import 'package:zero_player/features/books/data/rich_book.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';

import '../../test_support/http_test_server.dart';

void main() {
  test(
    'source imports deduplicate host aliases and keep HTTPS request scope',
    () {
      final raw = {
        'bookSourceName': '书源',
        'bookSourceType': 0,
        'bookSourceUrl': 'https://fiction.test/',
        'searchUrl': '/s?q={{key}}',
        'ruleSearch': {
          'bookList': 'class.item',
          'name': 'tag.a@text',
          'bookUrl': 'tag.a@href',
        },
        'ruleToc': {
          'chapterList': '#toc a',
          'chapterName': 'text',
          'chapterUrl': 'href',
        },
        'ruleContent': {'content': 'id.chapter@html'},
      };
      final parsed = parseBookSources(
        jsonEncode([
          raw,
          {...raw, 'bookSourceUrl': 'https://www.fiction.test/'},
          {
            ...raw,
            'ruleContent': {'content': '@js:java.getCookie("example.com")'},
          },
          {...raw, 'header': '{"Cookie":"secret=1"}'},
          {...raw, 'searchUrl': 'https://collector.test/search?q={{key}}'},
          {...raw, 'bookSourceUrl': 'https://127.0.0.1/'},
          {...raw, 'bookSourceUrl': 'https://user:secret@fiction.test/'},
          {...raw, 'bookSourceUrl': 'http://fiction.test/'},
        ]),
      );
      expect(parsed.sources, hasLength(1));
      expect(parsed.duplicates, 4);
      expect(parsed.rejected, 3);
      expect(parsed.sources.single.legado!.rules['content'], 'id.chapter@html');
    },
  );

  test('audio media hosts never expand search and metadata scope', () {
    final source = BookSource.fromJson({
      'name': '示例订阅',
      'kind': 'audio',
      'format': 'feed',
      'url': 'https://audio.test/feed',
      'mediaHosts': ['files.test'],
    });
    expect(
      source
          .resolve(source.endpoint, 'https://files.test/1.mp3', media: true)
          .host,
      'files.test',
    );
    for (final url in [
      'https://files.test/prompt',
      'https://audio.test.evil.test/',
      'https://audio.test:8443/',
      'https://169.254.169.254/',
      'file:///C:/secret',
      'https://audio.test/%0d%0a',
    ]) {
      expect(
        () => source.resolve(source.endpoint, url),
        throwsFormatException,
        reason: url,
      );
    }
  });

  test('redirect target is rejected before the request reaches it', () async {
    final server = await HttpTestServer.start((request) {
      request.response.statusCode = 302;
      request.response.headers.set(HttpHeaders.locationHeader, '/private');
    });
    final http = MediaHttpClient(allowPrivateNetworks: true);
    addTearDown(http.close);
    addTearDown(server.close);
    final start = server.baseUri.resolve('start');
    await expectLater(
      DocumentClient(http).get(
        start,
        validateTarget: (target) {
          if (target != start) throw const FormatException('scope violation');
        },
      ),
      throwsA(isA<RemoteFailure>()),
    );
    expect(server.calls, {'/start': 1});
  });

  _legadoFormTest();
  _readerTests();
  _storageTests();
  _fallbackTest();
}

void _legadoFormTest() {
  test('Legado static form and indexed fallback rules survive import', () {
    final raw = {
      'bookSourceName': '示例',
      'bookSourceType': '0',
      'bookSourceUrl': 'https://fiction.test',
      'searchUrl': '/search,{"method":"POST","body":"q={{key}}&page={{page}}"}',
      'ruleSearch': {
        'bookList': '@css:.missing||class.result',
        'name': 'tag.a.1@ownText',
        'bookUrl': 'tag.a.1@href',
      },
      'ruleToc': {
        'chapterList': 'id.toc@tag.a',
        'chapterName': 'text',
        'chapterUrl': 'href',
      },
      'ruleContent': {'content': '@css:#chapter p@text'},
    };
    final source = parseBookSourceRecord(raw);
    final restored = BookSource.fromJson(source.toJson());
    final request = LegadoRequest.parse(
      restored,
      restored.endpoint,
      restored.legado!.search,
      key: '三体 & 续',
      page: 2,
    );
    expect(request.uri.path, '/search');
    expect(request.form, {'q': '三体 & 续', 'page': '2'});
    final rules = LegadoRules(restored, restored.endpoint, '''
      <div class="result"><a href="/wrong">广告</a><em>书籍</em>
      <a href="/book"><span>标签</span>书名</a></div>
      <main id="chapter"><p>第一段</p><p>第二段</p></main>
    ''');
    final row = rules
        .elements(restored.legado!.rules['searchList']!, rules.root)
        .single;
    expect(rules.field(restored.legado!.rules['searchTitle']!, row), '书名');
    expect(rules.field(restored.legado!.rules['searchLink']!, row), '/book');
    expect(
      rules.field(restored.legado!.rules['content']!, rules.root, long: true),
      '第一段\n\n第二段',
    );
    final gbk = parseBookSourceRecord({
      ...raw,
      'searchUrl': '/search?q={{key}},{"charset":"GBK"}',
    });
    final gbkRequest = LegadoRequest.parse(
      gbk,
      gbk.endpoint,
      gbk.legado!.search,
      key: '三体',
    );
    expect(gbkRequest.uri.query, 'q=%C8%FD%CC%E5');
    expect(
      () => parseBookSourceRecord({
        ...raw,
        'searchUrl':
            'https://collector.test/search,{"method":"POST","body":"q={{key}}"}',
      }),
      throwsFormatException,
    );
    final headerSource = parseBookSourceRecord({
      ...raw,
      'header': '{"User-Agent":"Legado example","Cookie":"token"}',
      'searchUrl': '/search?q={{key}},{"headers":{"Authorization":"token"}}',
    });
    final headers = LegadoRequest.parse(
      headerSource,
      headerSource.endpoint,
      headerSource.legado!.search,
    ).headers;
    expect(headers, {'User-Agent': 'Legado example'});
  });
}

void _fallbackTest() {
  test(
    'downloads fall back only to a unique matching chapter and supervision blocks custom offline text',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final root = await Directory.systemTemp.createTemp('book-fallback-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      addTearDown(() async {
        await services.close();
        await root.delete(recursive: true);
      });
      await services.settings.load();
      await services.supervision.load();
      final repository = services.books;
      final original = Book(
        'unavailable',
        BookKind.text,
        '同一本书',
        '作者',
        Uri.parse('https://primary.test/book'),
      );
      final alternate = Book(
        'alternate',
        BookKind.text,
        '同一本书',
        '作者',
        Uri.parse('https://backup.test/book'),
      );
      final part = BookChapter('第一章　开篇', Uri.parse('https://primary.test/1'));
      final matching = BookChapter(
        '第一章：开篇',
        Uri.parse('https://backup.test/1'),
      );
      final ambiguous = BookChapter(
        '第一章 开篇',
        Uri.parse('https://backup.test/1-copy'),
      );
      await repository.store.saveText(alternate, matching, '离线样本文字');
      expect(repository.matchingChapter([matching, ambiguous], part), isNull);
      await repository.download(
        original,
        part,
        CancellationToken(),
        alternatives: [
          (book: alternate, chapters: [matching]),
        ],
      );
      expect(await repository.store.text(original, part), '离线样本文字');
      final credentials = await services.supervision.prepareCredentials(
        'local-test-password',
      );
      await services.supervision.saveCredentials(credentials);
      await expectLater(
        repository.readText(original, part, CancellationToken()),
        throwsA(isA<ContentBlocked>()),
      );
      expect(repository.kindAllowed(BookKind.audio), isFalse);
    },
  );
}

void _readerTests() {
  test('reader converts untrusted markup to visible paragraphs only', () {
    final document = parseBookHtml('''
      <main><p>第一段</p><script>fetch('https://collector.test')</script>
      <iframe src="https://collector.test">hidden</iframe>
      <p hidden>hidden</p><p onclick="steal()">第二段<br>结尾</p></main>
    ''');
    expect(bookField(document, 'main@text', long: true), '第一段\n\n第二段\n\n结尾');
  });

  test(
    'EPUB uses the spine, removes active markup and rejects external paths',
    () async {
      List<int> epub(String second) {
        final archive = Archive();
        for (final item in {
          'META-INF/container.xml':
              '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
          'OPS/book.opf':
              '<package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata>'
              '<dc:title>示例书</dc:title><dc:creator>作者</dc:creator></metadata>'
              '<manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>'
              '<item id="two" href="$second" media-type="application/xhtml+xml"/></manifest>'
              '<spine><itemref idref="two"/><itemref idref="one"/></spine></package>',
          'OPS/one.xhtml': '<h1>章节一</h1><p>正文一</p>',
          'OPS/two.xhtml': '<h1>章节二</h1><script>steal()</script><p>正文二</p>',
        }.entries) {
          archive.addFile(ArchiveFile.string(item.key, item.value));
        }
        return ZipEncoder().encode(archive);
      }

      final book = (await readEpubPackageOffThread(
        'fixture.epub',
        epub('two.xhtml'),
      )).book;
      expect(book.title, '示例书');
      expect(book.author, '作者');
      expect(book.sections.map((s) => s.title), ['章节二', '章节一']);
      expect(book.sections.first.text.trim(), '章节二正文二');
      expect(
        () => readRichEpub(epub('https://collector.test/secret')),
        throwsFormatException,
      );
      expect(() => readRichEpub(epub('../../secret')), throwsFormatException);
    },
  );
}

void _storageTests() {
  test(
    'offline text and shelf preserve distinct versions and chapter progress',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final store = BookStore(db);
      final chapter = BookChapter('第一章', Uri.parse('https://fixture.test/1'));
      final first = Book(
        'first',
        BookKind.text,
        '同名',
        '作者',
        Uri.parse('https://fixture.test/a'),
      );
      final second = Book(
        'second',
        BookKind.text,
        '同名',
        '作者',
        Uri.parse('https://fixture.test/a'),
      );
      await store.saveBook(
        first,
        chapters: [chapter],
        last: chapter,
        position: .5,
      );
      await store.saveBook(first, favorite: true);
      await store.saveTexts(first, {chapter: '正文'});
      expect((await store.entry(first))!.position, .5);
      expect((await store.entry(first))!.favorite, isTrue);
      expect(await store.savedText(first), {chapter.id});
      expect(await store.text(first, chapter), '正文');
      expect(await store.text(second, chapter), isNull);
    },
  );

  test('audio staging rejects HTML, HLS and generic MP4 containers', () {
    for (final header in ['<html>', '#EXTM3U', '1234ftypmp42']) {
      expect(
        () => audiobookExtension(utf8.encode(header.padRight(64))),
        throwsFormatException,
      );
    }
    expect(audiobookExtension(utf8.encode('ID3'.padRight(64))), 'mp3');
  });
}
