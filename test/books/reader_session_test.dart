import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/presentation/book_reader_page.dart';
import 'package:zero_player/features/books/presentation/reader_style.dart';
import 'package:zero_player/features/books/presentation/reader_pagination.dart';

void main() {
  testWidgets(
    'immersive lifecycle, toolbar dismissal and automatic reading pause',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      const readerChannel = MethodChannel('zero_player/platform');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        readerChannel,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.resetPadding);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('reader-session-'),
      ))!;
      final services = AppServices.scoped(root, AppDatabase.memory());
      addTearDown(() async {
        debugDefaultTargetPlatformOverride = null;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          readerChannel,
          null,
        );
        await tester.runAsync(() async {
          await services.close();
          await root.delete(recursive: true);
        });
      });
      await services.settings.load();
      await services.supervision.load();
      await services.books.store.write(
        'books_reader_preferences',
        const ReaderPreferences(autoSeconds: 2).toJson(),
      );
      final book = Book(
        'local',
        BookKind.text,
        '自动阅读测试',
        '',
        Uri.parse('book:session'),
      );
      final chapters = [
        BookChapter('第一章', Uri.parse('book:session#1')),
        BookChapter('第二章', Uri.parse('book:session#2')),
      ];
      await services.books.store.saveTexts(book, {
        for (final c in chapters)
          c: List.filled(40, '测试正文，自动阅读必须保持章节和页面顺序。').join('\n'),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: BookReaderPage(
            repository: services.books,
            book: book,
            chapters: chapters,
            initial: chapters.first,
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectImmersive(tester, calls);
      await tester.tap(find.byTooltip('阅读菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('下一页'), findsNothing);
      expect(find.textContaining('2 /'), findsOneWidget);
      await _enableAutomation(tester);
      expect(
        (await services.books.store.read('books_reader_preferences')
            as Map)['autoEnabled'],
        isTrue,
      );
      await tester.tap(find.byTooltip('自动阅读'));
      await tester.pump(const Duration(milliseconds: 2100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('3 /'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.byTooltip('停止自动阅读'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(calls.last.method, 'setReaderImmersive');
      expect(calls.last.arguments, isFalse);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

void _expectImmersive(WidgetTester tester, List<MethodCall> calls) {
  final viewport = tester.getRect(find.byType(ReaderViewport));
  expect(viewport.top, 0);
  expect(
    viewport.bottom,
    tester.view.physicalSize.height / tester.view.devicePixelRatio,
  );
  expect(
    calls.any(
      (call) => call.method == 'setReaderImmersive' && call.arguments == true,
    ),
    isTrue,
  );
}

Future<void> _enableAutomation(WidgetTester tester) async {
  await tester.tap(find.byTooltip('阅读菜单'));
  await tester.pumpAndSettle();
  expect(find.byTooltip('自动阅读'), findsNothing);
  await tester.tap(find.byTooltip('阅读样式'));
  await tester.pumpAndSettle();
  expect(find.text('翻页间隔（秒）'), findsNothing);
  expect(find.text('滚动速度'), findsNothing);
  await tester.tap(find.widgetWithText(SwitchListTile, '自动阅读'));
  await tester.pumpAndSettle();
  expect(find.text('翻页间隔（秒）'), findsOneWidget);
  expect(find.text('滚动速度'), findsOneWidget);
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}
