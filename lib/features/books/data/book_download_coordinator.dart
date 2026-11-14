import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/network/cancellation_token.dart';
import '../../supervision/domain/supervision_rules.dart';
import '../domain/book.dart';
import '../domain/book_download_plan.dart';
import 'books_repository.dart';

enum BookDownloadStatus { running, completed, paused, failed }

final class BookDownloadTask extends ChangeNotifier {
  BookDownloadTask(this.book, this.token, this.chapters);

  final Book book;
  final CancellationToken token;
  final List<BookChapter> chapters;
  late final Future<void> done;
  BookDownloadStatus status = BookDownloadStatus.running;
  int finished = 0;
  int total = 0;
  int failures = 0;
  final Set<String> savedChapterIds = {};
  String? error;

  void pause() => token.cancel();

  void changed() => notifyListeners();
}

/// Owns downloads for the lifetime of the repository, independently of routes.
final class BookDownloadCoordinator extends ChangeNotifier {
  BookDownloadCoordinator(this.repository, {this.downloadChapter}) {
    repository.policy.addListener(_policyChanged);
  }

  final BooksRepository repository;
  final Future<void> Function(Book, BookChapter, CancellationToken)?
  downloadChapter;
  final Map<String, BookDownloadTask> _tasks = {};
  bool _closed = false;

  BookDownloadTask? active(Book book) => _tasks[book.id];
  List<BookDownloadTask> get activeTasks => List.unmodifiable(_tasks.values);

  BookDownloadTask start(
    Book book,
    List<BookChapter> catalog,
    BookDownloadPlan plan, {
    bool keepPlan = true,
  }) {
    if (_closed) throw StateError('下载服务已关闭');
    final running = _tasks[book.id];
    if (running != null) return running;
    final task = BookDownloadTask(book, CancellationToken(), List.of(catalog));
    _tasks[book.id] = task;
    task.addListener(notifyListeners);
    task.done = _run(task, List.of(catalog), plan, keepPlan).whenComplete(() {
      task.removeListener(notifyListeners);
      notifyListeners();
    });
    notifyListeners();
    return task;
  }

  Future<void> removePlan(Book book) async {
    final task = active(book);
    if (task != null) {
      task.pause();
      await task.done;
    }
    await repository.store.write('books_download:${book.id}', null);
    notifyListeners();
  }

  Future<void> _run(
    BookDownloadTask task,
    List<BookChapter> catalog,
    BookDownloadPlan plan,
    bool keepPlan,
  ) async {
    final book = task.book;
    final token = task.token;
    final key = 'books_download:${book.id}';
    try {
      final ids = plan.chapterIds?.toSet();
      final range = ids == null
          ? catalog
                .skip(plan.first - 1)
                .take(plan.last - plan.first + 1)
                .toList()
          : catalog.where((chapter) => ids.contains(chapter.id)).toList();
      if (range.isEmpty) throw const FormatException('目录中已找不到所选章节');
      await repository.store.saveBook(book, chapters: catalog);
      if (keepPlan) {
        final savedPlan = BookDownloadPlan(
          plan.first,
          plan.last,
          plan.fallback,
          chapterIds:
              plan.chapterIds ?? range.map((chapter) => chapter.id).toList(),
        );
        await repository.store.write(key, savedPlan.toJson());
      }
      final saved = book.kind == BookKind.audio
          ? await repository.audioFiles.saved(book)
          : book.kind == BookKind.comic
          ? await repository.store.savedImages(book)
          : await repository.store.savedText(book);
      token.check();
      final chapters = range
          .where((chapter) => !saved.contains(chapter.id))
          .toList();
      task.total = chapters.length;
      task.changed();
      if (chapters.isEmpty) {
        if (keepPlan) await repository.store.write(key, null);
        task.status = BookDownloadStatus.completed;
        return;
      }
      token.check();
      Future<List<BookEdition>>? alternatives;
      var cursor = 0;
      Future<void> worker() async {
        while (cursor < chapters.length) {
          final chapter = chapters[cursor++];
          token.check();
          try {
            await _downloadOne(
              book,
              chapter,
              plan,
              token,
              () async => alternatives ??= repository.alternatives(book, token),
            );
            task.savedChapterIds.add(chapter.id);
          } on ContentBlocked {
            token.cancel();
            rethrow;
          } on Exception {
            token.check();
            task.failures++;
          }
          task.finished++;
          task.changed();
        }
      }

      await Future.wait(
        List.generate(
          math.min(book.kind == BookKind.text ? 3 : 2, chapters.length),
          (_) => worker(),
        ),
      );
      token.check();
      if (task.failures == 0 && keepPlan) {
        await repository.store.write(key, null);
      }
      task.status = BookDownloadStatus.completed;
    } on RequestCancelled {
      task.status = BookDownloadStatus.paused;
    } on ContentBlocked {
      task.status = BookDownloadStatus.paused;
      task.error = '内容策略已改变，下载已暂停';
    } on Exception catch (error) {
      task.status = BookDownloadStatus.failed;
      task.error = error is FormatException ? error.message : '下载未完成，请检查来源或网络';
    } finally {
      if (identical(_tasks[book.id], task)) _tasks.remove(book.id);
      task.changed();
    }
  }

  Future<void> _downloadOne(
    Book book,
    BookChapter chapter,
    BookDownloadPlan plan,
    CancellationToken token,
    Future<List<BookEdition>> Function() alternatives,
  ) async {
    try {
      if (downloadChapter case final callback?) {
        await callback(book, chapter, token);
      } else {
        await repository.download(book, chapter, token);
      }
    } on ContentBlocked {
      rethrow;
    } on Exception {
      token.check();
      if (!plan.fallback) rethrow;
      await repository.download(
        book,
        chapter,
        token,
        alternatives: await alternatives(),
        tryOriginal: false,
      );
    }
  }

  void _policyChanged() {
    for (final task in _tasks.values) {
      task.pause();
    }
  }

  Future<void> close() async {
    _closed = true;
    repository.policy.removeListener(_policyChanged);
    final tasks = _tasks.values.toList();
    for (final task in tasks) {
      task.pause();
    }
    await Future.wait(tasks.map((task) => task.done));
  }
}
