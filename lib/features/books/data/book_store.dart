import 'dart:convert';

import '../../../core/persistence/app_database.dart';
import '../domain/book.dart';

final class BookSourceEntry {
  const BookSourceEntry(
    this.source,
    this.enabled,
    this.favorite,
    this.group,
    this.health,
    this.checkedAt,
  );
  final BookSource source;
  final bool enabled, favorite;
  final String group, health;
  final int? checkedAt;
}

final class BookShelfEntry {
  const BookShelfEntry(
    this.book,
    this.chapters,
    this.last,
    this.position,
    this.favorite,
    this.updated,
  );
  final Book book;
  final List<BookChapter> chapters;
  final String? last;
  final double position;
  final bool favorite;
  final int updated;
}

final class BookStore {
  const BookStore(this.db);
  final AppDatabase db;

  Future<Object?> read(String key) async {
    final row = (await db.rows('SELECT value FROM app_meta WHERE key=?', [
      key,
    ])).firstOrNull;
    return row == null ? null : jsonDecode(row['value'] as String);
  }

  Future<void> write(String key, Object? value) => db.write(
    'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
    [key, jsonEncode(value)],
  );

  Future<List<BookSourceEntry>> sources(List<BookSource> builtins) async {
    final rows = await db.rows(
      "SELECT * FROM app_meta WHERE key GLOB 'books_source:*'",
    );
    final sources = {for (final source in builtins) source.id: source};
    final states = <String, Map>{};
    for (final row in rows) {
      try {
        final id = (row['key'] as String).substring('books_source:'.length);
        final state = jsonDecode(row['value'] as String) as Map;
        final custom = state['source'];
        if (!sources.containsKey(id) && custom is Map) {
          final source = BookSource.fromJson(custom);
          if (source.id == id) sources[id] = source;
        }
        states[id] = state;
      } catch (_) {
        // Keep damaged records available for recovery.
      }
    }
    return [
      for (final source in sources.values)
        BookSourceEntry(
          source,
          states[source.id]?['enabled'] as bool? ?? source.builtin,
          states[source.id]?['favorite'] as bool? ?? false,
          states[source.id]?['group'] as String? ?? source.group,
          states[source.id]?['health'] as String? ?? '',
          states[source.id]?['checkedAt'] as int?,
        ),
    ];
  }

  Future<void> saveSource(
    BookSource source,
    Map<String, Object?> changes,
  ) async {
    final key = 'books_source:${source.id}';
    await db.atomic(() async {
      final old = await read(key);
      await write(key, {
        if (old is Map) ...old,
        if (!source.builtin) 'source': source.toJson(),
        ...changes,
      });
    }, tables: {'app_meta'});
  }

  Future<void> deleteSource(BookSource source) => db.write(
    'DELETE FROM app_meta WHERE key=?',
    ['books_source:${source.id}'],
  );

  Future<List<BookShelfEntry>> shelf() async {
    final rows = await db.rows(
      "SELECT value FROM app_meta WHERE key GLOB 'books_shelf:*'",
    );
    final result = <BookShelfEntry>[];
    for (final row in rows) {
      try {
        result.add(_entry(jsonDecode(row['value'] as String) as Map));
      } catch (_) {
        // A bad record must not hide the rest of the shelf.
      }
    }
    return result..sort((a, b) => b.updated.compareTo(a.updated));
  }

  Future<BookShelfEntry?> entry(Book book) async {
    final raw = await read('books_shelf:${book.id}');
    return raw is Map ? _entry(raw) : null;
  }

  BookShelfEntry _entry(Map raw) => BookShelfEntry(
    Book.fromJson(raw['book'] as Map),
    (raw['chapters'] as List? ?? [])
        .whereType<Map>()
        .map(BookChapter.fromJson)
        .toList(),
    raw['last'] as String?,
    (raw['position'] as num?)?.toDouble() ?? 0,
    raw['favorite'] == true,
    raw['updated'] as int? ?? 0,
  );

  Future<void> saveBook(
    Book book, {
    List<BookChapter>? chapters,
    BookChapter? last,
    double? position,
    bool? favorite,
  }) async {
    final key = 'books_shelf:${book.id}';
    await db.atomic(() async {
      final old = await read(key);
      await write(key, {
        if (old is Map) ...old,
        'book': book.toJson(),
        if (chapters != null)
          'chapters': chapters.map((c) => c.toJson()).toList(),
        if (last != null) 'last': last.id,
        'position': ?position,
        'favorite': ?favorite,
        'updated': DateTime.now().millisecondsSinceEpoch,
      });
    }, tables: {'app_meta'});
  }

  String _textKey(Book book, BookChapter chapter) =>
      'books_text:${book.id}:${chapter.id}';

  Future<String?> text(Book book, BookChapter chapter) async =>
      await read(_textKey(book, chapter)) as String?;

  Future<void> saveText(Book book, BookChapter chapter, String text) async {
    await saveTexts(book, {chapter: text});
  }

  Future<void> saveTexts(Book book, Map<BookChapter, String> contents) async {
    final data = {
      for (final entry in contents.entries)
        _textKey(book, entry.key): jsonEncode(entry.value),
    };
    await db.atomic(() async {
      final used =
          (await db.rows(
                "SELECT COALESCE(SUM(length(CAST(value AS BLOB))),0) AS bytes FROM app_meta "
                "WHERE key GLOB 'books_text:*'",
              )).single['bytes']
              as int;
      final current = await db.rows(
        'SELECT key,length(CAST(value AS BLOB)) AS bytes FROM app_meta WHERE key GLOB ?',
        ['books_text:${book.id}:*'],
      );
      final replaced = current
          .where((row) => data.containsKey(row['key']))
          .fold<int>(0, (sum, row) => sum + (row['bytes'] as int));
      final bytes = data.values.fold<int>(
        0,
        (sum, value) => sum + utf8.encode(value).length,
      );
      if (used - replaced + bytes > 96 * 1024 * 1024) {
        throw const FormatException('离线正文空间已满');
      }
      for (final entry in data.entries) {
        await db.customStatement(
          'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
          [entry.key, entry.value],
        );
      }
    }, tables: {'app_meta'});
  }

  Future<void> removeLocal(Book book) => db.atomic(() async {
    await db.customStatement(
      'DELETE FROM app_meta WHERE key = ? OR key GLOB ?',
      ['books_shelf:${book.id}', 'books_text:${book.id}:*'],
    );
  }, tables: {'app_meta'});

  Future<Set<String>> savedText(Book book) async {
    final prefix = 'books_text:${book.id}:';
    final rows = await db.rows('SELECT key FROM app_meta WHERE key GLOB ?', [
      '$prefix*',
    ]);
    return {
      for (final row in rows) (row['key'] as String).substring(prefix.length),
    };
  }

  Future<void> deleteText(Book book, BookChapter chapter) =>
      db.write('DELETE FROM app_meta WHERE key=?', [_textKey(book, chapter)]);
}
