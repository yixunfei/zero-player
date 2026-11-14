import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/books/data/book_store.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/presentation/book_download_management_page.dart';
import 'package:zero_player/features/books/presentation/book_shelf_view.dart';

import '../../test_support/mobile_app_fixture.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('phone shelf filters and download manager fit $width px', (
      tester,
    ) async {
      final fixture = MobileAppFixture();
      await tester.runAsync(fixture.initialize);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 740);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final local = Book(
        'local',
        BookKind.text,
        '本地书籍',
        '作者',
        Uri.parse('file:///books/test.epub'),
      );
      final online = Book(
        'source',
        BookKind.text,
        '在线书籍',
        '作者',
        Uri.parse('https://fixture.test/book'),
        category: '科幻',
      );
      final chapter = BookChapter(
        '第一章',
        Uri.parse('https://fixture.test/chapter'),
      );
      await fixture.services.books.store.saveBook(online, chapters: [chapter]);
      await fixture.services.books.store.saveText(online, chapter, '正文');
      var checked = <BookShelfEntry>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookShelfView(
              repository: fixture.services.books,
              kind: BookKind.text,
              entries: [
                BookShelfEntry(local, const [], null, 0, false, 1),
                BookShelfEntry(online, [chapter], null, 0, false, 2),
              ],
              onOpen: (_) {},
              onFollowChanged: () {},
              onRefresh: () async {},
              onCheckUpdates: (entries) async => checked = entries,
              checking: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('全部状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('本地离线').last);
      await tester.pumpAndSettle();
      expect(find.text('本地书籍'), findsOneWidget);
      expect(find.text('在线书籍'), findsOneWidget);
      await tester.tap(find.text('本地离线').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('有更新').last);
      await tester.pumpAndSettle();
      expect(checked.map((entry) => entry.book.id), contains(online.id));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: BookDownloadManagementPage(services: fixture.services),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('书籍下载管理'), findsOneWidget);
      expect(find.text('在线书籍'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await fixture.finish(tester);
    });
  }
}
