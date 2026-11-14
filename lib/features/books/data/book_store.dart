import 'dart:convert';

import '../../../core/persistence/app_database.dart';
import '../domain/book.dart';
import '../domain/book_download_plan.dart';
import 'book_source_links.dart';
import 'book_mixed_content.dart';

final class BookSourceSubscription {
  const BookSourceSubscription(this.url, this.count, this.refreshedAt);
  final Uri url;
  final int count, refreshedAt;
  String get id => bookSubscriptionId(url);

  Map<String, Object> toJson() => {
    'url': url.toString(),
    'count': count,
    'refreshedAt': refreshedAt,
  };

  factory BookSourceSubscription.fromJson(Map data) => BookSourceSubscription(
    bookSourceLink(data['url'] as String),
    data['count'] as int,
    data['refreshedAt'] as int,
  );
}

final class BookSourceEntry {
  const BookSourceEntry(
    this.source,
    this.enabled,
    this.favorite,
    this.group,
    this.health,
    this.checkedAt, {
    this.subscriptionId,
    this.fromCatalog = false,
  });
  final BookSource source;
  final bool enabled, favorite;
  final String group, health;
  final int? checkedAt;
  final String? subscriptionId;
  final bool fromCatalog;

  BookSourceEntry withFavorite(bool value) => BookSourceEntry(
    source,
    enabled,
    value,
    group,
    health,
    checkedAt,
    subscriptionId: subscriptionId,
    fromCatalog: fromCatalog,
  );
}

/// Metadata from health checks does not change a source's discovery rules.
bool sameBookDiscoverySources(
  List<BookSourceEntry> current,
  List<BookSourceEntry> previous, {
  bool includeFavorites = false,
}) =>
    current.length == previous.length &&
    current.indexed.every((row) {
      final (index, entry) = row;
      final old = previous[index];
      return entry.source.id == old.source.id &&
          entry.enabled == old.enabled &&
          (!includeFavorites || entry.favorite == old.favorite) &&
          (identical(entry.source, old.source) ||
              _discoverySourceJson(entry.source) ==
                  _discoverySourceJson(old.source));
    });

String _discoverySourceJson(BookSource source) =>
    jsonEncode(source.toJson()..remove('updatedAt'));

final class BookShelfEntry {
  const BookShelfEntry(
    this.book,
    this.chapters,
    this.last,
    this.position,
    this.favorite,
    this.updated, {
    this.textOffset,
    this.following = false,
    this.newChapters = 0,
    this.chapterUpdatedAt,
  });
  final Book book;
  final List<BookChapter> chapters;
  final String? last;
  final double position;
  final int? textOffset;
  final bool following;
  final int newChapters;
  final DateTime? chapterUpdatedAt;
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

  Future<List<BookSourceEntry>> sources(
    List<BookSource> builtins, {
    bool enabledOnly = false,
  }) async {
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
        if (!sources.containsKey(id) &&
            custom is Map &&
            (!enabledOnly || state['enabled'] == true)) {
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
        if (states[source.id]?['removed'] != true &&
            (!enabledOnly ||
                (states[source.id]?['enabled'] ??
                        (source.builtin && source.defaultEnabled)) ==
                    true))
          _sourceEntry(source, states[source.id] ?? const {}),
    ];
  }

  Future<BookSourceEntry?> source(BookSource? builtin, String id) async {
    try {
      final state = await read('books_source:$id');
      final data = state is Map ? state : const {};
      if (data['removed'] == true) return null;
      final custom = data['source'];
      final source =
          builtin ?? (custom is Map ? BookSource.fromJson(custom) : null);
      return source?.id == id ? _sourceEntry(source!, data) : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  BookSourceEntry _sourceEntry(BookSource source, Map state) => BookSourceEntry(
    source,
    state['enabled'] is bool
        ? state['enabled'] as bool
        : source.builtin && source.defaultEnabled,
    state['favorite'] == true,
    state['group'] is String ? state['group'] as String : source.group,
    state['health'] is String ? state['health'] as String : '',
    state['checkedAt'] is int ? state['checkedAt'] as int : null,
    subscriptionId: state['subscription'] is String
        ? state['subscription'] as String
        : null,
    fromCatalog: state['catalog'] == true,
  );

  Future<void> saveSource(
    BookSource source,
    Map<String, Object?> changes,
  ) async {
    final key = 'books_source:${source.id}';
    await db.atomic(() async {
      final old = await read(key);
      if ((!source.builtin && old is! Map) ||
          (old is Map && old['removed'] == true)) {
        throw const FormatException('该来源已移除');
      }
      await write(key, {if (old is Map) ...old, ...changes});
    }, tables: {'app_meta'});
  }

  Future<void> deleteSource(BookSource source) => source.builtin
      ? write('books_source:${source.id}', {'removed': true})
      : db.write('DELETE FROM app_meta WHERE key=?', [
          'books_source:${source.id}',
        ]);

  Future<Map<String, String>> blockedSources() async {
    final value = await read('books_source_blacklist');
    return value is Map ? Map<String, String>.from(value) : {};
  }

  Future<Set<String>> blockedAliases() async {
    final value = await read('books_source_blacklist_aliases');
    return value is Map ? value.keys.whereType<String>().toSet() : {};
  }

  Future<void> setSourcesEnabled(Set<String> ids, bool enabled) async {
    final rows = await db.rows(
      "SELECT key,value FROM app_meta WHERE key GLOB 'books_source:*'",
    );
    final states = {for (final row in rows) row['key']: row['value'] as String};
    await db.batch((batch) {
      for (final id in ids) {
        final key = 'books_source:$id';
        final old = states[key];
        final state = old == null
            ? <String, Object?>{}
            : jsonDecode(old) as Map;
        batch.customStatement(
          'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
          [
            key,
            jsonEncode({...state, 'enabled': enabled}),
          ],
        );
      }
    });
  }

  Future<void> writeImported(
    List<({BookSource source, BookSourceEntry? previous})> entries, {
    String? subscriptionId,
    bool fromCatalog = false,
  }) => db.batch((batch) {
    for (final (:source, :previous) in entries) {
      batch.customStatement(
        'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
        [
          'books_source:${source.id}',
          jsonEncode({
            'source': source.toJson(),
            'enabled': previous?.enabled ?? false,
            'favorite': previous?.favorite ?? false,
            if (previous != null) 'group': previous.group,
            'subscription': ?subscriptionId,
            if (fromCatalog) 'catalog': true,
          }),
        ],
      );
    }
  });

  Future<List<BookSourceSubscription>> subscriptions() async {
    final rows = await db.rows(
      "SELECT value FROM app_meta WHERE key GLOB 'books_subscription:*'",
    );
    final result = <BookSourceSubscription>[];
    for (final row in rows) {
      try {
        result.add(
          BookSourceSubscription.fromJson(
            jsonDecode(row['value'] as String) as Map,
          ),
        );
      } on Object {
        // A damaged bookmark does not hide other subscriptions.
      }
    }
    return result..sort((a, b) => b.refreshedAt.compareTo(a.refreshedAt));
  }

  Future<void> saveSubscription(BookSourceSubscription subscription) =>
      write('books_subscription:${subscription.id}', subscription.toJson());

  Future<void> deleteSubscription(BookSourceSubscription subscription) =>
      db.write('DELETE FROM app_meta WHERE key=?', [
        'books_subscription:${subscription.id}',
      ]);

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

  Future<Map<String, BookDownloadPlan>> downloadPlans() async {
    final rows = await db.rows(
      "SELECT key,value FROM app_meta WHERE key GLOB 'books_download:*'",
    );
    final plans = <String, BookDownloadPlan>{};
    for (final row in rows) {
      try {
        final plan = BookDownloadPlan.fromJson(
          jsonDecode(row['value'] as String),
        );
        if (plan != null) {
          plans[(row['key'] as String).substring('books_download:'.length)] =
              plan;
        }
      } on Object {
        // A damaged plan does not hide other downloads.
      }
    }
    return plans;
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
    textOffset: raw['textOffset'] is int ? raw['textOffset'] as int : null,
    following: raw['following'] == true,
    newChapters: raw['newChapters'] as int? ?? 0,
    chapterUpdatedAt: switch (raw['chapterUpdatedAt']) {
      final int timestamp => DateTime.fromMillisecondsSinceEpoch(timestamp),
      _ => null,
    },
  );

  Future<void> saveBook(
    Book book, {
    List<BookChapter>? chapters,
    BookChapter? last,
    double? position,
    int? textOffset,
    bool? favorite,
    bool? following,
    bool clearUpdates = false,
  }) async {
    final key = 'books_shelf:${book.id}';
    await db.atomic(() async {
      final old = await read(key);
      await write(key, {
        if (old is Map) ...old,
        'book': book.toJson(),
        if (chapters != null)
          'chapters': _chapterRecords(
            chapters,
            old,
            preserve: following ?? (old is Map && old['following'] == true),
          ),
        if (last != null) 'last': last.id,
        'position': ?position,
        if (position != null ||
            (last != null && (old is! Map || old['last'] != last.id)))
          'textOffset': textOffset,
        'favorite': ?favorite,
        'following': ?following,
        if (clearUpdates || following == false) 'newChapters': 0,
        'updated': DateTime.now().millisecondsSinceEpoch,
      });
    }, tables: {'app_meta'});
  }

  Future<void> saveRichPosition(
    Book book,
    BookChapter chapter, {
    required int index,
    required bool horizontal,
    required int verticalPage,
    required double offset,
    required double fraction,
  }) => db.atomic(() async {
    if (await entry(book) == null) return;
    await write('rich_position_${book.id}', {
      'index': index,
      'horizontal': horizontal,
      'verticalPage': verticalPage,
      'offset': offset,
    });
    await saveBook(book, last: chapter, position: fraction);
  }, tables: {'app_meta'});

  Future<void> updateFollowedChapters(Book book, List<BookChapter> fresh) =>
      updateShelfChapters(book, fresh, followedOnly: true);

  Future<void> updateShelfChapters(
    Book book,
    List<BookChapter> fresh, {
    bool followedOnly = false,
  }) => db.atomic(() async {
    final key = 'books_shelf:${book.id}';
    final raw = await read(key);
    if (raw is! Map || (followedOnly && raw['following'] != true)) return;
    final previous = _entry(raw);
    final tail = previous.chapters.lastOrNull;
    final boundary = fresh.indexWhere((chapter) => chapter.id == tail?.id);
    final known = previous.chapters.map((chapter) => chapter.id).toSet();
    final added = boundary < 0
        ? 0
        : fresh
              .skip(boundary + 1)
              .where((chapter) => !known.contains(chapter.id))
              .length;
    // Keep cached chapters with local progress or downloads when a feed rotates.
    final merged = {
      for (final chapter in previous.chapters) chapter.id: chapter,
    };
    for (final chapter in fresh) {
      merged[chapter.id] = chapter;
    }
    if (merged.length > 4000) return;
    await write(key, {
      ...raw,
      'chapters': merged.values.map((chapter) => chapter.toJson()).toList(),
      'newChapters': previous.newChapters + added,
      if (added > 0) 'chapterUpdatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }, tables: {'app_meta'});

  List<Object?> _chapterRecords(
    List<BookChapter> chapters,
    Object? raw, {
    required bool preserve,
  }) {
    if (!preserve || raw is! Map || raw['chapters'] is! List) {
      return chapters.map((chapter) => chapter.toJson()).toList();
    }
    final old = _entry(raw).chapters;
    final newer = {for (final chapter in old) chapter.id: chapter};
    for (final chapter in chapters) {
      newer[chapter.id] = chapter;
    }
    return newer.values.take(4000).map((chapter) => chapter.toJson()).toList();
  }

  String _textKey(Book book, BookChapter chapter) =>
      'books_text:${book.id}:${chapter.id}';

  Future<String?> text(Book book, BookChapter chapter) async =>
      await read(_textKey(book, chapter)) as String?;

  String _readingCacheKey(Book book, BookChapter chapter) =>
      'books_read_cache:${book.id}:${chapter.id}';

  Future<String?> readingCache(Book book, BookChapter chapter) async =>
      await read(_readingCacheKey(book, chapter)) as String?;

  Future<void> cacheReading(Book book, BookChapter chapter, String text) async {
    final value = jsonEncode(text);
    final size = utf8.encode(value).length;
    if (size > 2 * 1024 * 1024) return;
    await db.atomic(() async {
      final key = _readingCacheKey(book, chapter);
      await db.customStatement(
        'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
        [key, value],
      );
      final rows = await db.rows(
        "SELECT key,length(CAST(value AS BLOB)) AS bytes FROM app_meta "
        "WHERE key GLOB 'books_read_cache:*' ORDER BY rowid DESC",
      );
      var used = 0;
      for (final row in rows) {
        used += row['bytes'] as int;
        if (used > 24 * 1024 * 1024) {
          await db.customStatement('DELETE FROM app_meta WHERE key=?', [
            row['key'],
          ]);
        }
      }
    }, tables: {'app_meta'});
  }

  Future<void> clearReadingCache([Book? book]) => db.atomic(() async {
    await db.customStatement('DELETE FROM app_meta WHERE key GLOB ?', [
      book == null ? 'books_read_cache:*' : 'books_read_cache:${book.id}:*',
    ]);
    await db.customStatement('DELETE FROM app_meta WHERE key GLOB ?', [
      book == null ? 'books_image_cache:*' : 'books_image_cache:${book.id}:*',
    ]);
    await db.customStatement('DELETE FROM app_meta WHERE key GLOB ?', [
      book == null ? 'books_mixed_cache:*' : 'books_mixed_cache:${book.id}:*',
    ]);
  }, tables: {'app_meta'});

  String _mixedKey(Book book, BookChapter chapter) =>
      'books_mixed_cache:${book.id}:${chapter.id}';

  Future<List<BookChapterSegment>> mixedReading(
    Book book,
    BookChapter chapter,
  ) async {
    final raw = await read(_mixedKey(book, chapter));
    if (raw is! List) return const [];
    try {
      return [
        for (final part in raw.cast<Map>())
          if (part['text'] is String)
            BookTextSegment(part['text'] as String)
          else if (part['image'] is String)
            BookImageSegment(Uri.parse(part['image'] as String)),
      ];
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> cacheMixedReading(
    Book book,
    BookChapter chapter,
    List<BookChapterSegment> parts,
  ) async {
    final value = jsonEncode([
      for (final part in parts)
        switch (part) {
          BookTextSegment text => {'text': text.text},
          BookImageSegment image => {'image': image.address.toString()},
        },
    ]);
    if (value.length > 512 * 1024) return;
    await db.atomic(() async {
      await db.customStatement(
        'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
        [_mixedKey(book, chapter), value],
      );
      final rows = await db.rows(
        "SELECT key,length(CAST(value AS BLOB)) AS bytes FROM app_meta "
        "WHERE key GLOB 'books_mixed_cache:*' ORDER BY rowid DESC",
      );
      var used = 0;
      for (final row in rows) {
        used += row['bytes'] as int;
        if (used > 24 * 1024 * 1024) {
          await db.customStatement('DELETE FROM app_meta WHERE key=?', [
            row['key'],
          ]);
        }
      }
    }, tables: {'app_meta'});
  }

  String _imageCacheKey(Book book, Uri image) =>
      'books_image_cache:${book.id}:${base64UrlEncode(utf8.encode(image.toString()))}';

  Future<List<int>?> readingImage(Book book, Uri image) async {
    final encoded = await read(_imageCacheKey(book, image));
    if (encoded is! String) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> cacheReadingImage(Book book, Uri image, List<int> bytes) async {
    if (bytes.length > 4 * 1024 * 1024) return;
    await db.atomic(() async {
      await db.customStatement(
        'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
        [_imageCacheKey(book, image), jsonEncode(base64Encode(bytes))],
      );
      final rows = await db.rows(
        "SELECT key,length(CAST(value AS BLOB)) AS bytes FROM app_meta "
        "WHERE key GLOB 'books_image_cache:*' ORDER BY rowid DESC",
      );
      var used = 0;
      for (final row in rows) {
        used += row['bytes'] as int;
        if (used > 24 * 1024 * 1024) {
          await db.customStatement('DELETE FROM app_meta WHERE key=?', [
            row['key'],
          ]);
        }
      }
    }, tables: {'app_meta'});
  }

  String _offlineImageKey(Book book, BookChapter chapter) =>
      'books_image_offline:${book.id}:${chapter.id}';

  String _offlineImagePartPrefix(Book book, BookChapter chapter) =>
      'books_image_data:${book.id}:${chapter.id}:';

  Future<List<Uri>?> offlineImageAddresses(
    Book book,
    BookChapter chapter,
  ) async {
    final raw = await read(_offlineImageKey(book, chapter));
    if (raw is! List) return null;
    try {
      return raw.cast<String>().map(Uri.parse).toList();
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<List<int>?> offlineImageBytes(
    Book book,
    BookChapter chapter,
    Uri image,
  ) async {
    final addresses = await offlineImageAddresses(book, chapter);
    final index = addresses?.indexOf(image) ?? -1;
    if (index < 0) return null;
    final raw = await read('${_offlineImagePartPrefix(book, chapter)}$index');
    if (raw is! String) return null;
    try {
      return base64Decode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<Map<Uri, List<int>>?> offlineImages(
    Book book,
    BookChapter chapter,
  ) async {
    final addresses = await offlineImageAddresses(book, chapter);
    if (addresses == null) return null;
    final images = <Uri, List<int>>{};
    for (var index = 0; index < addresses.length; index++) {
      final raw = await read('${_offlineImagePartPrefix(book, chapter)}$index');
      if (raw is! String) return null;
      try {
        images[addresses[index]] = base64Decode(raw);
      } on FormatException {
        return null;
      }
    }
    return images;
  }

  Future<void> saveOfflineImages(
    Book book,
    BookChapter chapter,
    Map<Uri, List<int>> images,
    Future<void> Function() validate,
  ) async {
    if (images.isEmpty || images.length > 100) {
      throw const FormatException('章节图片数量无效');
    }
    final values = [
      for (final bytes in images.values) jsonEncode(base64Encode(bytes)),
    ];
    final bytes = values.fold<int>(0, (total, value) => total + value.length);
    if (bytes > 48 * 1024 * 1024) {
      throw const FormatException('单章图片超过离线空间限制');
    }
    await db.atomic(() async {
      final key = _offlineImageKey(book, chapter);
      final prefix = _offlineImagePartPrefix(book, chapter);
      final used =
          (await db.rows(
                "SELECT COALESCE(SUM(length(CAST(value AS BLOB))),0) AS bytes "
                "FROM app_meta WHERE key GLOB 'books_image_data:*' AND key NOT GLOB ?",
                ['$prefix*'],
              )).single['bytes']
              as int;
      if (used + bytes > 192 * 1024 * 1024) {
        throw const FormatException('离线图片空间已满');
      }
      await validate();
      await db.customStatement('DELETE FROM app_meta WHERE key GLOB ?', [
        '$prefix*',
      ]);
      for (var index = 0; index < values.length; index++) {
        await db.customStatement(
          'INSERT INTO app_meta(key,value) VALUES(?,?)',
          ['$prefix$index', values[index]],
        );
      }
      await db.customStatement(
        'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
        [key, jsonEncode(images.keys.map((uri) => uri.toString()).toList())],
      );
    }, tables: {'app_meta'});
  }

  Future<Set<String>> savedImages(Book book) async {
    final prefix = 'books_image_offline:${book.id}:';
    final rows = await db.rows('SELECT key FROM app_meta WHERE key GLOB ?', [
      '$prefix*',
    ]);
    return {
      for (final row in rows) (row['key'] as String).substring(prefix.length),
    };
  }

  Future<void> deleteImages(Book book, BookChapter chapter) =>
      db.atomic(() async {
        await db.customStatement('DELETE FROM app_meta WHERE key=?', [
          _offlineImageKey(book, chapter),
        ]);
        await db.customStatement('DELETE FROM app_meta WHERE key GLOB ?', [
          '${_offlineImagePartPrefix(book, chapter)}*',
        ]);
      }, tables: {'app_meta'});

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

  Future<List<Map>> annotations(Book book) async {
    final raw = await read('books_notes:${book.id}');
    return raw is List ? raw.whereType<Map>().toList() : [];
  }

  Future<void> addAnnotation(Book book, Map<String, Object?> entry) =>
      db.atomic(() async {
        final entries = await annotations(book);
        if (entries.length >= 1000) {
          throw const FormatException('每本书最多保存 1000 条记录');
        }
        await write('books_notes:${book.id}', [entry, ...entries]);
      }, tables: {'app_meta'});

  Future<void> deleteAnnotation(Book book, String id) => db.atomic(() async {
    final entries = await annotations(book);
    await write(
      'books_notes:${book.id}',
      entries.where((e) => e['id'] != id).toList(),
    );
  }, tables: {'app_meta'});

  Future<void> removeLocal(Book book) => db.atomic(() async {
    await db.customStatement(
      'DELETE FROM app_meta WHERE key IN (?, ?, ?, ?) OR key GLOB ? OR key GLOB ? OR key GLOB ? OR key GLOB ? OR key GLOB ? OR key GLOB ?',
      [
        'books_shelf:${book.id}',
        'books_notes:${book.id}',
        'rich_position_${book.id}',
        'publication_${book.id}',
        'books_text:${book.id}:*',
        'books_read_cache:${book.id}:*',
        'books_image_cache:${book.id}:*',
        'books_image_offline:${book.id}:*',
        'books_image_data:${book.id}:*',
        'books_mixed_cache:${book.id}:*',
      ],
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

  Future<void> clearOffline(Book book) => db.atomic(() async {
    final patterns = book.kind == BookKind.comic
        ? ['books_image_offline:${book.id}:*', 'books_image_data:${book.id}:*']
        : ['books_text:${book.id}:*'];
    for (final pattern in patterns) {
      await db.customStatement('DELETE FROM app_meta WHERE key GLOB ?', [
        pattern,
      ]);
    }
  }, tables: {'app_meta'});
}
