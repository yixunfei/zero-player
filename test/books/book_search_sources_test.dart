import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/book_store.dart';
import 'package:zero_player/features/books/domain/book.dart';

void main() {
  test(
    'search reuses source snapshot and keeps preferred source first',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final root = await Directory.systemTemp.createTemp(
        'book-search-sources-',
      );
      final services = AppServices.scoped(root, AppDatabase.memory());
      addTearDown(() async {
        await services.close();
        await root.delete(recursive: true);
      });
      await services.settings.load();
      await services.supervision.load();
      BookSource source(String host) => BookSource.fromJson({
        'name': host,
        'url': 'https://$host/',
        'kind': 'text',
        'format': 'featured',
        'featured': [
          {'title': '星际小说', 'url': '/book'},
        ],
        'rules': {
          'chapters': 'a',
          'chapterTitle': '@text',
          'chapterUrl': '@href',
          'content': 'p@text',
        },
      });
      final preferred = source('preferred.test');
      final favorite = source('favorite.test');
      final disabled = source('disabled.test');
      BookSourceEntry entry(
        BookSource source, {
        bool favorite = false,
        bool enabled = true,
      }) => BookSourceEntry(source, enabled, favorite, '', '', null);
      final order = <String>[];
      final result = await services.books.find(
        BookKind.text,
        '星际',
        CancellationToken(),
        preferredSource: preferred.id,
        maxSources: 2,
        availableSources: [
          entry(favorite, favorite: true),
          entry(disabled, enabled: false),
          entry(preferred),
        ],
        onProgress: (update) {
          if (update.sourceId != null) order.add(update.sourceId!);
        },
      );
      expect(order, [preferred.id, favorite.id]);
      expect(result.books.map((book) => book.sourceId), [
        preferred.id,
        favorite.id,
      ]);
    },
  );
}
