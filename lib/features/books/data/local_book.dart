import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/network/document_encoding.dart';
import '../domain/book.dart';

typedef LocalBook = ({
  String title,
  String author,
  List<({String title, String text})> sections,
});

const maxLocalBookBytes = 128 * 1024 * 1024;

Future<Uint8List> readLocalBookBytes(File file) async {
  const invalidSize = FormatException('电子书大小须在 128 MiB 以内且内容非空');
  if (await file.length() > maxLocalBookBytes) throw invalidSize;
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in file.openRead(0, maxLocalBookBytes + 1)) {
    buffer.add(chunk);
  }
  if (buffer.isEmpty || buffer.length > maxLocalBookBytes) throw invalidSize;
  return buffer.takeBytes();
}

Future<LocalBook> parseTextBookOffThread(String filename, List<int> bytes) =>
    Isolate.run(() => _txt(p.basenameWithoutExtension(filename), bytes));

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
