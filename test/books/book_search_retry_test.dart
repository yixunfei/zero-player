import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/presentation/book_search_page.dart';

void main() {
  testWidgets(
    'retry keeps successful results and only refreshes failed sources',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('book-search-retry-'),
      ))!;
      final services = AppServices.scoped(root, AppDatabase.memory());
      await services.settings.load();
      await services.supervision.load();
      addTearDown(() async {
        await tester.runAsync(() async {
          await services.close();
          await root.delete(recursive: true);
        });
      });
      final repo = services.books;
      for (final entry in await repo.sources(
        BookKind.text,
        enabledOnly: true,
      )) {
        await repo.saveSource(entry.source, {'enabled': false});
      }
      final existing = _featured('existing.test', '已找到的星际小说');
      final failed = _featured('dict.cn', '被识别为词典');
      await repo.importSources([existing, failed]);
      await repo.saveSource(existing, {'enabled': true});
      await repo.saveSource(failed, {'enabled': true});
      await tester.pumpWidget(
        MaterialApp(
          home: BookSearchPage(
            repository: repo,
            kind: BookKind.text,
            query: '星际',
            onOpen: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已找到的星际小说'), findsOneWidget);
      expect(find.text('重试失败渠道'), findsOneWidget);

      final added = _featured('added.test', '新启用的星际小说');
      await repo.saveSource(failed, {'enabled': false});
      await repo.importSources([added]);
      await repo.saveSource(added, {'enabled': true});

      await tester.tap(find.text('重试失败渠道'));
      await tester.pumpAndSettle();
      expect(find.text('已找到的星际小说'), findsOneWidget);
      expect(find.text('新启用的星际小说'), findsNothing);
      expect(find.text('重试失败渠道'), findsNothing);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      expect(find.text('新启用的星际小说'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

const _rules = {
  'chapters': 'a',
  'chapterTitle': '@text',
  'chapterUrl': '@href',
  'content': 'p@text',
};

BookSource _featured(String host, String title) => BookSource.fromJson({
  'name': host,
  'url': 'https://$host/',
  'format': 'featured',
  'kind': 'text',
  'featured': [
    {'title': title, 'url': '/book'},
  ],
  'rules': _rules,
});
