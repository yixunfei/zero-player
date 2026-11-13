import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';

enum PublicationCollection {
  literature('文学与通识', ['Gutenberg', '好读', '好读二代']),
  academic('学术专著', ['DOAB']),
  technical('技术图书', ['书栈网', 'Gutenberg']);

  const PublicationCollection(this.label, this.sources);
  final String label;
  final List<String> sources;

  static final _engineering = RegExp(
    r'(?:^|;\s*)Category: Engineering & Technology(?:;|$)',
  );

  static PublicationCollection forBook(Map<String, dynamic> row) =>
      switch (row['source']) {
        'DOAB' => academic,
        '书栈网' => technical,
        'Gutenberg'
            when _engineering.hasMatch(row['category'] as String? ?? '') =>
          technical,
        _ => literature,
      };
}

enum PublicationLanguage {
  chinese('中文', ['zh', 'zho', 'chi']),
  english('英语', ['en', 'eng']),
  other('其他语种', []);

  const PublicationLanguage(this.label, this.codes);
  final String label;
  final List<String> codes;

  bool matches(String language) {
    final tags = language
        .toLowerCase()
        .split(RegExp(r'[;,\s]+'))
        .where((tag) => tag.isNotEmpty)
        .map((tag) => tag.split('-').first);
    if (this == other) {
      return tags.any(
        (tag) => !chinese.codes.contains(tag) && !english.codes.contains(tag),
      );
    }
    return tags.any(codes.contains);
  }
}

String publicationLanguageLabel(String language) {
  if (language.isEmpty) return '';
  return language
      .split(RegExp(r'\s*[;,]\s*'))
      .map(
        (value) => switch (value) {
          'zh' || 'chi' || 'zho' => '中文',
          'zh-Hant' => '繁体中文',
          'en' || 'eng' => '英语',
          'de' || 'ger' || 'deu' => '德语',
          'fr' || 'fre' || 'fra' => '法语',
          'es' || 'spa' => '西班牙语',
          'it' || 'ita' => '意大利语',
          _ => value,
        },
      )
      .toSet()
      .join('、');
}

String publicationQuery(String query) {
  const aliases = {
    '维吉尔': 'virgil',
    '維吉爾': 'virgil',
    '维吉尔斯': 'virgil',
    'vergil': 'virgil',
    '维吉利乌斯': 'virgil',
  };
  final q = query.trim().toLowerCase();
  return aliases[q] ?? q;
}

bool publicationMatches(Map<String, dynamic> row, String input, String field) {
  final query = publicationQuery(input);
  if (query == 'virgil' &&
      input.trim().toLowerCase() != 'virgil' &&
      field != '书名') {
    return RegExp(
      r'(^|;\s*)Virgil,',
      caseSensitive: false,
    ).hasMatch('${row['author']}');
  }
  return (field == '作者'
          ? '${row['author']}'
          : field == '书名'
          ? '${row['title']}'
          : '${row['title']} ${row['author']} ${row['category']}')
      .toLowerCase()
      .contains(query);
}

class PublicCatalog {
  static Future<List<Map<String, dynamic>>>? _loading;
  static Future<List<Map<String, dynamic>>> load() =>
      _loading ??= _read().onError<Object>((error, stack) {
        _loading = null;
        Error.throwWithStackTrace(error, stack);
      });
  static Future<List<Map<String, dynamic>>> _read() async {
    final data = await rootBundle.load('assets/catalogs/books/public.json.gz');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    return Isolate.run(
      () => (jsonDecode(utf8.decode(gzip.decode(bytes))) as List)
          .cast<Map<String, dynamic>>(),
    );
  }
}
