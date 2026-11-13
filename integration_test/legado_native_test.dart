import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/book_client.dart';
import 'package:zero_player/features/books/data/book_import.dart';
import 'package:zero_player/features/books/data/legado/legado_worker.dart';
import 'package:zero_player/features/books/domain/book.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _testSandbox();
  _testPublishedSource();
  _testPublishedCollection();
}

void _testSandbox() {
  testWidgets(
    'Legado QuickJS rules run with bounded data helpers',
    (tester) async {
      final source = _scriptSource(
        '@js:heading(java.getString("article@text"))',
        library: 'function heading(value) { return "书：" + value; }',
      );
      final token = CancellationToken();
      final result = await runLegadoJob(
        LegadoJob(
          source,
          source.endpoint,
          LegadoOperation.content,
          input: '<article>正文</article>',
        ),
        token,
      );
      expect(result.content, '书：正文');

      final sandbox = _scriptSource(
        '@js:[typeof fetch,typeof Packages,typeof java.getCookie,typeof process,typeof require].join(",")',
      );
      final isolation = await runLegadoJob(
        LegadoJob(sandbox, sandbox.endpoint, LegadoOperation.content),
        token,
      );
      expect(
        isolation.content,
        'undefined,undefined,undefined,undefined,undefined',
      );

      final stalled = _scriptSource('@js:while(true){}');
      await expectLater(
        runLegadoJob(
          LegadoJob(stalled, stalled.endpoint, LegadoOperation.content),
          token,
        ),
        throwsFormatException,
      );
      final client = MediaHttpClient();
      try {
        final external = _scriptSource(
          '@js:"未请求"',
          search: '@js:java.ajax("https://unauthorized.test/books")',
        );
        await expectLater(
          BookClient(DocumentClient(client)).books(external, '书名', token),
          throwsFormatException,
        );
      } finally {
        client.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );
}

void _testPublishedSource() {
  testWidgets(
    'published Legado link imports, persists and reads with original rules',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('zero-legado-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      try {
        await services.settings.load();
        await services.supervision.load();
        await tester.pumpWidget(const SizedBox());
        final repository = services.books;
        final token = CancellationToken();
        const detail =
            'https://www.yckceo.com/yuedu/shuyuan/content/id/8081.html';
        final import = await repository.subscribe(
          'legado://import/bookSource?src=${Uri.encodeComponent(detail)}',
          token,
        );
        final source = import.parsed.sources.single;
        expect(source.legado, isNotNull);
        expect(import.changes.duplicates + import.changes.added, 1);
        expect(
          (await repository.subscriptions()).single.url.toString(),
          detail,
        );
        final books = await repository.client.books(source, '三体', token);
        final book = books.firstWhere((book) => book.title.contains('三体'));
        final chapters = await repository.client.chapters(source, book, token);
        expect(chapters.length, greaterThan(1));
        final text = await repository.client.text(
          source,
          chapters.first,
          token,
          book: book,
        );
        expect(text.length, greaterThan(100));
      } finally {
        await services.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

void _testPublishedCollection() {
  testWidgets(
    'published Legado collection imports thousands of sources in one pass',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('zero-legado-bulk-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      try {
        await services.settings.load();
        await services.supervision.load();
        await tester.pumpWidget(const SizedBox());
        const detail =
            'https://www.yckceo.com/yuedu/shuyuans/content/id/559.html';
        final books = services.books;
        final result = await books.subscribe(
          'legado://import/bookSource?src=${Uri.encodeComponent(detail)}',
          CancellationToken(),
        );
        expect(result.parsed.duplicates, greaterThan(0));
        expect(result.changes.added, greaterThan(1000));
        final imported = [
          ...await books.sources(BookKind.text),
          ...await books.sources(BookKind.audio),
        ].where((entry) => !entry.source.builtin).toList();
        expect(imported, hasLength(result.changes.added));
        expect(imported.every((entry) => !entry.enabled), isTrue);
        debugPrint(
          'Parsed ${result.parsed.sources.length} distinct sources, '
          'added ${result.changes.added}, '
          'duplicates ${result.parsed.duplicates + result.changes.duplicates}, '
          'rejected ${result.parsed.rejected}, skipped ${result.changes.skipped}',
        );
      } finally {
        await services.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

BookSource _scriptSource(
  String content, {
  String library = '',
  String search = '/search?q={{key}}',
}) => parseBookSourceRecord({
  'bookSourceName': '脚本样本',
  'bookSourceUrl': 'https://example.test/',
  'searchUrl': search,
  'ruleContent': {'content': content},
  'jsLib': library,
});
