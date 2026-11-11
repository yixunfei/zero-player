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
    'curated sources deliver chapters and Gutenberg plays offline',
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
        expect(textSources.length, 4);
        await Future.wait(
          textSources.map((entry) async {
            final source = entry.source;
            final discovery = await books.client.books(source, '', token);
            expect(discovery, isNotEmpty, reason: source.name);
            final results = await books.client.books(
              source,
              source.sample,
              token,
            );
            expect(results, isNotEmpty, reason: source.name);
            final work = results.first;
            final chapters = await books.chapters(work, token);
            expect(chapters, isNotEmpty, reason: source.name);
            final body = await books.readText(work, chapters.first, token);
            expect(body.length, greaterThan(100), reason: source.name);
            await books.download(work, chapters.first, token);
            expect(
              await books.store.text(work, chapters.first),
              body,
              reason: source.name,
            );
          }),
        );

        final audioSource = (await books.sources(BookKind.audio)).single.source;
        final library = await books.client.books(audioSource, '', token);
        expect(library.length, 2);
        for (final work in library) {
          final chapters = await books.chapters(work, token);
          expect(chapters.length, greaterThan(1), reason: work.title);
          final chapter = chapters.first;
          await books.download(work, chapter, token);
          final session = await books.audioFiles.open(work, chapter);
          final engine = services.createAudiobookEngine();
          try {
            await engine.open(session.uri);
            for (
              var i = 0;
              i < 80 && engine.snapshot.position.inSeconds < 2;
              i++
            ) {
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
      } finally {
        await services.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
