import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/book_download_coordinator.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/domain/book_download_plan.dart';

void main() {
  test(
    'paused download resumes with bounded concurrency and cleans up',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final root = await Directory.systemTemp.createTemp('book-download-task-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      addTearDown(() async {
        await services.close();
        await root.delete(recursive: true);
      });
      await services.settings.load();
      await services.supervision.load();
      final book = Book(
        'source',
        BookKind.text,
        '后台下载测试',
        '作者',
        Uri.parse('https://fixture.test/book'),
      );
      final chapters = List.generate(
        6,
        (index) => BookChapter(
          '第${index + 1}章',
          Uri.parse('https://fixture.test/${index + 1}'),
        ),
      );
      var active = 0, peak = 0, started = 0;
      var gate = Completer<void>();
      var firstThree = Completer<void>();
      final coordinator = BookDownloadCoordinator(
        services.books,
        downloadChapter: (book, chapter, token) async {
          active++;
          started++;
          if (active > peak) peak = active;
          if (started == 3 && !firstThree.isCompleted) firstThree.complete();
          try {
            await gate.future;
            token.check();
            await services.books.store.saveText(book, chapter, chapter.title);
          } finally {
            active--;
          }
        },
      );
      addTearDown(coordinator.close);
      const plan = BookDownloadPlan(1, 6, false);
      final immediate = coordinator.start(book, chapters, plan);
      immediate.pause();
      await immediate.done;
      expect(immediate.status, BookDownloadStatus.paused);
      expect(
        await services.books.store.read('books_download:${book.id}'),
        isNotNull,
      );

      final first = coordinator.start(book, chapters, plan);
      await firstThree.future.timeout(const Duration(seconds: 5));
      expect(coordinator.active(book), same(first));
      expect(peak, 3);
      first.pause();
      gate.complete();
      await first.done;
      expect(first.status, BookDownloadStatus.paused);
      expect(coordinator.active(book), isNull);
      expect(
        await services.books.store.read('books_download:${book.id}'),
        isNotNull,
      );

      gate = Completer<void>()..complete();
      firstThree = Completer<void>();
      started = 0;
      final resumed = coordinator.start(book, chapters, plan);
      await resumed.done.timeout(const Duration(seconds: 5));
      expect(resumed.status, BookDownloadStatus.completed);
      expect(resumed.failures, 0);
      expect(resumed.finished, 6);
      expect(peak, 3);
      expect(await services.books.store.savedText(book), hasLength(6));
      expect(
        await services.books.store.read('books_download:${book.id}'),
        isNull,
      );
      expect(coordinator.active(book), isNull);
    },
  );
}
