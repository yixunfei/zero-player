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
import 'package:zero_player/features/books/data/local_book.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';

import '../../test_support/http_test_server.dart';

void main() {
  test(
    'source imports deduplicate host aliases and reject executable rules',
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
      expect(parsed.duplicates, 1);
      expect(parsed.rejected, 6);
      expect(parsed.sources.single.rules['content'], '#chapter@text');
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

  _readerTests();
  _storageTests();
  _fallbackTest();
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

  test('EPUB uses the spine, removes active markup and rejects external paths', () {
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

    final book = parseLocalBook('fixture.epub', epub('two.xhtml'));
    expect(book.title, '示例书');
    expect(book.author, '作者');
    expect(book.sections.map((s) => s.title), ['章节二', '章节一']);
    expect(book.sections.first.text, '章节二\n\n正文二');
    expect(
      () =>
          parseLocalBook('fixture.epub', epub('https://collector.test/secret')),
      throwsFormatException,
    );
    expect(
      () => parseLocalBook('fixture.epub', epub('../../secret')),
      throwsFormatException,
    );
  });
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
