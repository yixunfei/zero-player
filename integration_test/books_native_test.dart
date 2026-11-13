import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/domain/book.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets(
    'curated reading sources deliver searchable chapters and offline text',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('zero-books-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      try {
        await services.settings.load();
        await services.supervision.load();
        await tester.pumpWidget(const SizedBox());
        final books = services.books;
        final token = CancellationToken();
        final textSources = await books.sources(BookKind.text);
        expect(textSources.length, greaterThanOrEqualTo(12));
        expect(
          textSources.every((entry) => entry.source.format != BookFormat.feed),
          isTrue,
        );
        await Future.wait(
          textSources.map((entry) async {
            final source = entry.source;
            if (source.hasDiscovery) {
              final discovery = await books.client.books(source, '', token);
              expect(discovery, isNotEmpty, reason: source.name);
            }
            final results = await books.client.books(
              source,
              source.sample,
              token,
            );
            expect(results, isNotEmpty, reason: source.name);
            final work = results.firstWhere(
              (result) =>
                  bookIdentity(result.title) == bookIdentity(source.sample),
              orElse: () => results.first,
            );
            final chapters = await books.chapters(work, token);
            expect(chapters, isNotEmpty, reason: source.name);
            final chapter = chapters
                .take(6)
                .firstWhere(
                  (chapter) => RegExp(r'第.{1,12}[章节回]').hasMatch(chapter.title),
                  orElse: () => chapters.first,
                );
            final body = await books.readText(work, chapter, token);
            expect(body.length, greaterThan(100), reason: source.name);
            await books.download(work, chapter, token);
            expect(
              await books.store.text(work, chapter),
              body,
              reason: source.name,
            );
          }),
        );
      } finally {
        await services.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'audiobooks and podcast feeds download and play offline',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('zero-audiobooks-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      try {
        await services.settings.load();
        await services.supervision.load();
        await tester.pumpWidget(const SizedBox());
        final books = services.books;
        final token = CancellationToken();
        final sources = await books.sources(BookKind.audio);
        expect(sources.length, greaterThanOrEqualTo(3));
        for (final entry in sources) {
          final library = await books.client.books(entry.source, '', token);
          expect(library, isNotEmpty, reason: entry.source.name);
          for (final work in library) {
            final chapters = await books.chapters(work, token);
            expect(chapters.length, greaterThan(1), reason: work.title);
            await _playChapter(tester, services, work, chapters.first, token);
          }
        }
      } finally {
        await services.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<void> _playChapter(
  WidgetTester tester,
  AppServices services,
  Book work,
  BookChapter chapter,
  CancellationToken token,
) async {
  final books = services.books;
  await books.download(work, chapter, token);
  final session = await books.audioFiles.open(work, chapter);
  final engine = services.createAudiobookEngine();
  try {
    await engine.open(session.uri);
    for (var i = 0; i < 80 && engine.snapshot.position.inSeconds < 2; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      engine.snapshot.duration.inSeconds,
      greaterThan(2),
      reason: work.title,
    );
    expect(
      engine.snapshot.position.inSeconds,
      greaterThanOrEqualTo(2),
      reason: work.title,
    );
  } finally {
    await engine.dispose();
    session.close();
  }
}
