import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

final class FileTransfer {
  static Future<String?> readText({int maxBytes = 20 * 1024 * 1024}) async {
    final selected = await openFile();
    if (selected == null) return null;
    if (await selected.length() > maxBytes) {
      throw const FormatException('文件超过大小限制');
    }
    return selected.readAsString();
  }

  static Future<void> saveText(String name, String text) async {
    final directory = await (await getTemporaryDirectory()).createTemp(
      'zero-save-',
    );
    final file = File('${directory.path}/$name');
    try {
      await file.writeAsString(text, flush: true);
      await saveFile(file, name, 'application/octet-stream');
    } finally {
      await directory.delete(recursive: true);
    }
  }

  static Future<void> saveFile(File file, String name, String mime) async {
    if (Platform.isAndroid) {
      await const MethodChannel('zero_player/platform').invokeMethod<bool>(
        'saveFile',
        {'path': file.path, 'name': name, 'mime': mime},
      );
    } else {
      final destination = await getSaveLocation(suggestedName: name);
      if (destination != null) await file.copy(destination.path);
    }
  }
}
