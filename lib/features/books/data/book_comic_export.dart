import 'dart:isolate';

import 'package:archive/archive.dart';

typedef ComicExportImage = ({String path, List<int> bytes});

/// Encodes in a worker so large chapters do not stall reader controls.
Future<List<int>> encodeComicArchive(
  List<ComicExportImage> files,
  String indexText,
) => Isolate.run(() {
  final archive = Archive()..addFile(ArchiveFile.string('章节目录.txt', indexText));
  for (final entry in files) {
    archive.addFile(ArchiveFile(entry.path, entry.bytes.length, entry.bytes));
  }
  return ZipEncoder().encode(archive);
});
