import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/public_catalog.dart';
import 'package:zero_player/features/books/data/rich_book.dart';
import 'package:zero_player/features/books/presentation/reader_style.dart';

import '../../test_support/public_book_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _publicCatalog();
  _epubParsing();
  _svgSecurity();
  _importFailures();
  test(
    'immersive and automation speeds persist and clamp untrusted preferences',
    () {
      final p = ReaderPreferences.fromJson({
        'immersive': false,
        'autoSeconds': -2,
        'scrollSpeed': 999,
      });
      expect(p.immersive, isFalse);
      expect(p.autoSeconds, 2);
      expect(p.scrollSpeed, 150);
      expect(ReaderPreferences.fromJson(p.toJson()).toJson(), p.toJson());
      expect(const ReaderPreferences().immersive, isTrue);
    },
  );
}

void _publicCatalog() {
  test(
    'public catalog has real Virgil editions and translator metadata',
    () async {
      final rows = await PublicCatalog.load();
      final virgil = rows
          .where(
            (r) =>
                r['source'] == 'Gutenberg' &&
                publicationMatches(r, '维吉尔', '作者'),
          )
          .toList();
      expect(virgil.length, greaterThanOrEqualTo(20));
      expect(virgil.any((r) => '${r['author']}'.contains('Finlay')), isFalse);
      expect(
        virgil.any(
          (r) =>
              r['title'] == 'The Aeneid' && '${r['author']}'.contains('Dryden'),
        ),
        isTrue,
      );
      expect(
        rows.map((r) => r['source']).toSet(),
        containsAll(
          PublicationCollection.values
              .expand((collection) => collection.sources)
              .toSet(),
        ),
      );
      expect(
        rows
            .where(
              (r) =>
                  PublicationCollection.forBook(r) ==
                  PublicationCollection.academic,
            )
            .length,
        greaterThan(50),
      );
      final technical = rows.where(
        (r) =>
            PublicationCollection.forBook(r) == PublicationCollection.technical,
      );
      expect(
        technical.map((r) => r['title']),
        containsAll(['Docker 从入门到实践', 'The Project Gutenberg RST Manual']),
      );
      expect(
        virgil.map(PublicationCollection.forBook),
        everyElement(PublicationCollection.literature),
      );
    },
  );
}

void _epubParsing() {
  test('EPUB keeps code and embedded artwork, removes active content', () {
    final section = readRichEpub(sampleEpub()).single;
    expect(
      section.html,
      contains('<pre><code>docker run hello-world\n  --example'),
    );
    expect(section.html, contains('data:image/png;base64,'));
    expect(section.html, contains('data:image/svg+xml;base64,'));
    expect(section.html, contains('<ruby>漢<rt>hàn</rt></ruby>'));
    expect(section.html, isNot(contains('evil.test')));
    expect(section.html, isNot(contains('<script')));
  });
  test(
    'EPUB detects vertical typesetting and never fetches external images',
    () {
      final section = readRichEpub(
        sampleEpub(image: 'https://evil.test/p.png', vertical: true),
      ).single;
      expect(section.vertical, isTrue);
      expect(section.html, isNot(contains('evil.test')));
    },
  );
  test('EPUB refuses archive traversal and corrupt containers', () {
    final zip = Archive()..addFile(ArchiveFile.string('../outside', 'bad'));
    expect(() => readRichEpub(ZipEncoder().encode(zip)), throwsFormatException);
    expect(() => readRichEpub(utf8.encode('not a zip')), throwsA(anything));
  });
  test('EPUB rejects a symlink marked in the ZIP directory', () {
    final bytes = Uint8List.fromList(sampleEpub());
    final zip = ByteData.sublistView(bytes);
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    final entry = directory.centralDirectoryOffset;
    zip.setUint8(entry + 5, 3);
    zip.setUint32(entry + 38, 0xa000 << 16, Endian.little);
    expect(() => readRichEpub(bytes), throwsFormatException);
  });
  test('EPUB tolerates invalid SVG and retains a local SVG image alt', () {
    final broken = readRichEpub(
      sampleEpub(image: 'data:image/svg+xml;base64,broken!'),
    ).single;
    expect(broken.text, contains('中文正文'));
    expect(broken.html, isNot(contains('broken!')));

    final archive = ZipDecoder().decodeBytes(sampleEpub());
    archive.addFile(
      ArchiveFile.string(
        'OEBPS/picture.svg',
        '<svg xmlns="http://www.w3.org/2000/svg"><text>图中文字</text></svg>',
      ),
    );
    final chapter = utf8.decode(
      archive.findFile('OEBPS/chapter.xhtml')!.content,
    );
    archive.addFile(
      ArchiveFile.string(
        'OEBPS/chapter.xhtml',
        chapter.replaceFirst(
          'src="picture.png"',
          'src="picture.svg" alt="原始图注"',
        ),
      ),
    );
    final section = readRichEpub(ZipEncoder().encode(archive)).single;
    expect(section.text, contains('原始图注 图中文字'));
  });
  test('EPUB local CSS preserves cascade and strips network resources', () {
    final archive = ZipDecoder().decodeBytes(sampleEpub());
    archive.addFile(
      ArchiveFile.string(
        'OEBPS/style.css',
        'body {text-align:justify} p {text-indent:2em;color:blue} p {color:red;background:url(https://evil.test/a)}',
      ),
    );
    final section = readRichEpub(ZipEncoder().encode(archive)).single;
    expect(section.html, contains('text-indent:2em'));
    expect(section.html, contains('color:red'));
    expect(section.html, contains('text-align:justify'));
    expect(section.html, isNot(contains('evil.test')));
  });
}

void _importFailures() {
  test(
    'failed document promotion leaves the shelf and offline text unchanged',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'book-import-failure-',
      );
      final services = AppServices.scoped(root, AppDatabase.memory());
      addTearDown(() async {
        await services.close();
        await root.delete(recursive: true);
      });
      final repo = services.books;
      final file = await File(
        '${root.path}/sample.epub',
      ).writeAsBytes(sampleEpub());
      final book = await repo.importLocal(file);
      await repo.removeLocalBook(book);
      final target = repo.documentFile(book, 'epub');
      final conflict = await Directory(target.path).create();
      const catalog = {'source': 'Gutenberg', 'author': '目录作者'};
      await expectLater(
        repo.importLocal(file, catalogMetadata: catalog),
        throwsA(isA<FileSystemException>()),
      );
      expect(await repo.store.entry(book), isNull);
      expect(await repo.store.read('publication_${book.id}'), isNull);
      expect(await repo.store.savedText(book), isEmpty);
      expect(await repo.documents.list().map((entry) => entry.path).toList(), [
        conflict.path,
      ]);
      await conflict.delete();
      await repo.importLocal(file, catalogMetadata: catalog);
      expect(await target.readAsBytes(), await file.readAsBytes());
      final metadata = await repo.store.read('publication_${book.id}') as Map;
      expect(metadata['source'], 'Gutenberg');
      expect(metadata['author'], book.author);
    },
  );
  test(
    'EPUB import accepts large XHTML with a small visible chapter',
    () async {
      final root = await Directory.systemTemp.createTemp('book-import-large-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      addTearDown(() async {
        await services.close();
        await root.delete(recursive: true);
      });
      final archive = ZipDecoder().decodeBytes(sampleEpub());
      final chapter = utf8.decode(
        archive.findFile('OEBPS/chapter.xhtml')!.content,
      );
      final padding = 'x' * (2 * 1024 * 1024);
      archive.addFile(
        ArchiveFile.string('OEBPS/chapter.xhtml', '<!--$padding-->$chapter'),
      );
      final file = await File(
        '${root.path}/sample.epub',
      ).writeAsBytes(ZipEncoder().encode(archive));
      final book = await services.books.importLocal(file);
      final shelf = (await services.books.store.entry(book))!;
      expect(book.title, '测试');
      expect(book.author, '作者');
      expect(shelf.chapters.single.title, '第一章');
      expect(
        await services.books.store.text(book, shelf.chapters.single),
        contains('中文正文'),
      );
    },
  );
}

void _svgSecurity() {
  test(
    'EPUB sanitizes authored SVG data and retains text for content policy',
    () {
      final svg =
          '<svg xmlns="http://www.w3.org/2000/svg"><style>@import url(https://evil.test/a);</style><script>bad()</script><text>policy-visible</text><image href="https://evil.test/a"/></svg>';
      final section = readRichEpub(
        sampleEpub(
          image: 'data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}',
        ),
      ).single;
      expect(section.text, contains('policy-visible'));
      final images = RegExp(
        r'data:image/svg\+xml;base64,([^" ]+)',
      ).allMatches(section.html);
      for (final image in images) {
        final decoded = utf8.decode(base64Decode(image[1]!));
        expect(decoded, isNot(contains('<script')));
        expect(decoded, isNot(contains('<style')));
        expect(decoded, isNot(contains('evil.test')));
      }
    },
  );
}
