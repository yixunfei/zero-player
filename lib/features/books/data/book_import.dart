import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';

import '../../../core/network/document_encoding.dart';
import '../../sources/data/jsonc_decoder.dart';
import '../domain/book.dart';
import 'book_source_links.dart';
import 'legado/legado_import.dart';

final class BookSourceImport {
  const BookSourceImport(this.sources, this.duplicates, this.issues);
  final List<BookSource> sources;
  final int duplicates;
  final Map<String, int> issues;
  int get rejected => issues.values.fold(0, (sum, count) => sum + count);

  String get issueSummary {
    if (issues.isEmpty) return '';
    final sorted = issues.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return '（${sorted.take(3).map((issue) => '${issue.key} ${issue.value}').join('、')}）';
  }
}

Future<BookSourceImport> parseBookSourcesOffThread(String input) =>
    Isolate.run(() => parseBookSources(input));

Future<BookSourceImport> readBookSourceFile(String path) => Isolate.run(
  () async {
    final handle = await File(path).open();
    try {
      final length = await handle.length();
      if (length > maxBookSourceBytes) {
        throw const FormatException('来源文件超过 64 MiB');
      }
      final bytes = await handle.read(length + 1);
      if (bytes.length != length) throw const FormatException('来源文件在导入期间发生变化');
      return parseBookSourceBytes(bytes);
    } finally {
      await handle.close();
    }
  },
);

BookSourceImport parseBookSourceBytes(List<int> bytes) {
  if (bytes.length > maxBookSourceBytes) {
    throw const FormatException('来源文件超过 64 MiB');
  }
  final zip =
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      ((bytes[2] == 3 && bytes[3] == 4) || (bytes[2] == 5 && bytes[3] == 6));
  return zip
      ? parseBookSourceRecords(_zipRecords(bytes))
      : parseBookSources(decodeDocumentText(bytes));
}

BookSourceImport parseBookSources(String input) =>
    parseBookSourceRecords(_decodeRecords(input));

Iterable<Object?> _decodeRecords(String input) {
  if (input.length > maxBookSourceBytes) {
    throw const FormatException('来源文件超过 64 MiB');
  }
  final text = input.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
  Object? raw;
  try {
    raw = jsonDecode(text);
  } on FormatException {
    raw = decodeJsonc(text);
  }
  return _sourceRecords(raw);
}

Iterable<Object?> _zipRecords(List<int> bytes) sync* {
  final directory = ZipDirectory()..read(InputMemoryStream(bytes));
  if (directory.fileHeaders.length > 4000) {
    throw const FormatException('备份条目过多');
  }
  const names = {
    'booksource.json',
    'book_sources.json',
    'rsssource.json',
    'rss_sources.json',
  };
  final selected = <String, ZipFile>{};
  for (final header in directory.fileHeaders) {
    final file = header.file;
    if (file == null) continue;
    final name = file.filename
        .replaceAll(r'\', '/')
        .split('/')
        .last
        .toLowerCase();
    if (!names.contains(name)) continue;
    if (selected.containsKey(name) ||
        (header.versionMadeBy >> 8 == 3 &&
            (header.externalFileAttributes >> 16) & 0xf000 == 0xa000) ||
        file.flags & 1 != 0) {
      throw const FormatException('备份中的书源文件重复、加密或使用符号链接');
    }
    selected[name] = file;
  }
  if (selected.isEmpty) throw const FormatException('备份中没有 Legado 书源或订阅文件');
  var remaining = maxBookSourceBytes;
  for (final file in selected.values) {
    final size = file.uncompressedSize;
    if (size < 0 || size > remaining) {
      throw const FormatException('解压后的书源文件超过 64 MiB');
    }
    remaining -= size;
    final output = OutputMemoryStream(size: size);
    file.decompress(output);
    final data = output.getBytes();
    if (data.length != size || getCrc32(data) != file.crc32) {
      throw const FormatException('备份中的书源文件校验失败');
    }
    yield* _decodeRecords(decodeDocumentText(data));
  }
}

BookSourceImport parseBookSourceRecords(Iterable<Object?> records) {
  final sources = <String, BookSource>{};
  final versions = <String, int>{};
  final issues = <String, int>{};
  var duplicates = 0;
  var count = 0;
  for (final record in records) {
    if (++count > 12000) throw const FormatException('单次导入最多解析 12000 条记录');
    try {
      final source = parseBookSourceRecord(record);
      final version = source.updatedAt;
      final previous = versions[source.id];
      if (previous != null) duplicates++;
      if (previous == null || version > previous) {
        versions[source.id] = version;
        sources[source.id] = source;
      }
    } on FormatException catch (error) {
      issues.update(error.message, (count) => count + 1, ifAbsent: () => 1);
    } on Object {
      issues.update('记录格式无效', (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return BookSourceImport(sources.values.toList(), duplicates, issues);
}

Iterable<Object?> _sourceRecords(Object? value, [int depth = 0]) sync* {
  if (depth > 4) throw const FormatException('来源清单嵌套过深');
  if (value is List) {
    for (final record in value) {
      yield* _sourceRecords(record, depth + 1);
    }
  } else if (value is Map &&
      !value.containsKey('bookSourceUrl') &&
      !value.containsKey('sourceUrl') &&
      !value.containsKey('format')) {
    final collections = const [
      'bookSources',
      'bookSource',
      'rssSources',
      'rssSource',
      'sources',
      'data',
    ].where((key) => value[key] is List || value[key] is Map);
    if (collections.isEmpty) yield value;
    for (final key in collections) {
      yield* _sourceRecords(value[key], depth + 1);
    }
  } else {
    yield value;
  }
}

BookSource parseBookSourceRecord(Object? record) {
  if (record is! Map) throw const FormatException('记录格式无效');
  if (record.containsKey('bookSourceUrl')) return importLegadoBook(record);
  if (record.containsKey('sourceUrl')) return importLegadoFeed(record);
  return BookSource.fromJson(record);
}
