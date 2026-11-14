import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/books/data/book_comic_export.dart';

void main() {
  test('comic export keeps image order and chapter names', () async {
    final bytes = await encodeComicArchive([
      (path: '0001/0001.jpg', bytes: [1, 2, 3]),
      (path: '0001/0002.png', bytes: [4, 5]),
    ], '0001  第一话');
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.files.map((file) => file.name), [
      '章节目录.txt',
      '0001/0001.jpg',
      '0001/0002.png',
    ]);
    expect(utf8.decode(archive.files.first.content as List<int>), '0001  第一话');
    expect(archive.files[1].content, [1, 2, 3]);
  });
}
