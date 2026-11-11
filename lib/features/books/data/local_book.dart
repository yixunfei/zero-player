import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../../core/network/document_encoding.dart';
import '../domain/book.dart';
import 'book_html.dart';

typedef LocalBook = ({
  String title,
  String author,
  List<({String title, String text})> sections,
});

LocalBook parseLocalBook(String filename, List<int> bytes) =>
    p.extension(filename).toLowerCase() == '.epub'
    ? _epub(p.basenameWithoutExtension(filename), bytes)
    : _txt(p.basenameWithoutExtension(filename), bytes);

LocalBook _txt(String title, List<int> bytes) {
  final text = decodeDocumentText(bytes);
  if (text.contains('\u0000')) throw const FormatException('文件不是支持的文本编码');
  final sections = <({String title, String text})>[];
  final buffer = StringBuffer();
  final heading = RegExp(r'^\s*第.{1,12}[章节卷回篇]');
  void finish() {
    final body = buffer.toString().trim();
    buffer.clear();
    if (body.isEmpty) return;
    final line = body.split('\n').first;
    sections.add((
      title: line.length < 80 && heading.hasMatch(line)
          ? bookLabel(line)
          : '第 ${sections.length + 1} 节',
      text: body,
    ));
  }

  for (final line in const LineSplitter().convert(text)) {
    if (buffer.length >= 20000 ||
        (line.length < 80 && heading.hasMatch(line))) {
      finish();
    }
    if (line.length > 250000) throw const FormatException('TXT 单行超过大小限制');
    buffer.writeln(line);
  }
  finish();
  return (title: bookLabel(title), author: '', sections: sections);
}

LocalBook _epub(String title, List<int> bytes) {
  final directory = ZipDirectory()..read(InputMemoryStream(bytes));
  if (directory.fileHeaders.length > 4000) {
    throw const FormatException('EPUB 条目过多');
  }
  final files = <String, ZipFile>{};
  for (final header in directory.fileHeaders) {
    final file = header.file!;
    if (files.containsKey(file.filename)) {
      throw const FormatException('EPUB 含重复路径');
    }
    if (header.versionMadeBy >> 8 == 3 &&
        (header.externalFileAttributes >> 16) & 0xf000 == 0xa000) {
      throw const FormatException('EPUB 含符号链接');
    }
    files[file.filename] = file;
  }
  if (files.containsKey('META-INF/encryption.xml')) {
    throw const FormatException('不支持加密 EPUB');
  }
  var remaining = 24 * 1024 * 1024;
  String read(String path) {
    final file = files[path];
    if (file == null ||
        file.uncompressedSize < 0 ||
        file.uncompressedSize > 2 * 1024 * 1024 ||
        file.uncompressedSize > remaining ||
        file.flags & 1 != 0) {
      throw const FormatException('EPUB 章节缺失、加密或超出大小限制');
    }
    remaining -= file.uncompressedSize;
    final output = OutputMemoryStream(size: file.uncompressedSize);
    file.decompress(output);
    final data = output.getBytes();
    if (data.length != file.uncompressedSize || getCrc32(data) != file.crc32) {
      throw const FormatException('EPUB 文件校验失败');
    }
    return decodeDocumentText(data);
  }

  XmlElement xml(String path) {
    final text = read(path);
    if (RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(text)) {
      throw const FormatException('EPUB 元数据含 XML 实体或文档类型声明');
    }
    return XmlDocument.parse(text).rootElement;
  }

  final container = xml('META-INF/container.xml');
  final packagePath = container.descendantElements
      .where((e) => e.name.local == 'rootfile')
      .firstOrNull
      ?.getAttribute('full-path');
  if (packagePath == null) throw const FormatException('EPUB 缺少书籍清单');
  final package = xml(_epubPath('', packagePath));
  final manifest = package.childElements
      .where((e) => e.name.local == 'manifest')
      .firstOrNull;
  final spine = package.childElements
      .where((e) => e.name.local == 'spine')
      .firstOrNull;
  if (manifest == null || spine == null) {
    throw const FormatException('EPUB 缺少阅读顺序');
  }
  final chapters = <String, String>{
    for (final item in manifest.childElements)
      if (const {
            'application/xhtml+xml',
            'text/html',
          }.contains(item.getAttribute('media-type')) &&
          item.getAttribute('id') != null &&
          item.getAttribute('href') != null)
        item.getAttribute('id')!: item.getAttribute('href')!,
  };
  final sections = _readSpine(
    spine,
    chapters,
    p.posix.dirname(packagePath),
    read,
  );
  final metadata = package.childElements
      .where((e) => e.name.local == 'metadata')
      .firstOrNull;
  String field(String name) => bookLabel(
    metadata?.childElements
        .where((e) => e.name.local == name)
        .firstOrNull
        ?.innerText,
  );
  final label = field('title');
  return (
    title: label.isEmpty ? bookLabel(title) : label,
    author: field('creator'),
    sections: sections,
  );
}

List<({String title, String text})> _readSpine(
  XmlElement spine,
  Map<String, String> chapters,
  String folder,
  String Function(String path) read,
) {
  final sections = <({String title, String text})>[];
  final seen = <String>{};
  for (final item in spine.childElements) {
    final href = chapters[item.getAttribute('idref')];
    if (href == null) continue;
    final path = _epubPath(folder, href);
    if (!seen.add(path)) continue;
    if (seen.length > 600) throw const FormatException('EPUB 正文章节过多');
    final document = parseBookHtml(read(path));
    final body = document.body;
    if (body == null) continue;
    final text = plainBookText(body, limit: 250001);
    if (text.length > 250000) throw const FormatException('EPUB 单章正文过长');
    if (text.isEmpty) continue;
    final heading = bookLabel(body.querySelector('h1, h2, h3')?.text);
    sections.add((
      title: heading.isEmpty ? '第 ${sections.length + 1} 节' : heading,
      text: text,
    ));
  }
  return sections;
}

String _epubPath(String folder, String href) {
  final uri = Uri.parse(href);
  final path = p.posix.normalize(
    p.posix.join(folder, Uri.decodeComponent(uri.path)),
  );
  if (uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      p.posix.isAbsolute(path) ||
      path.contains('\\') ||
      path.contains('\u0000') ||
      path == '..' ||
      path.startsWith('../')) {
    throw const FormatException('EPUB 清单路径超出文件范围');
  }
  return path;
}
