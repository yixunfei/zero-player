import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Publish a same-volume temporary file without replacing an existing target.
Future<void> publishFile(File temporary, File target) async {
  if (Platform.isWindows) {
    final move = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)
        >('MoveFileW');
    final from = temporary.absolute.path.toNativeUtf16();
    final to = target.absolute.path.toNativeUtf16();
    try {
      if (move(from, to) == 0) {
        throw FileSystemException('无法保存，目标可能已存在或目录不可写', target.path);
      }
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
  } else {
    // The non-Windows desktop fallback reserves the name without replacement.
    await target.create(exclusive: true);
    try {
      await temporary.copy(target.path);
      await temporary.delete();
    } catch (_) {
      await target.delete();
      rethrow;
    }
  }
}
