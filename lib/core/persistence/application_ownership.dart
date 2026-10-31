import 'local_open_channel.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Holds the application data directory until all services have shut down.
final class ApplicationOwnership {
  ApplicationOwnership._(this._file, this.channel);
  final LocalOpenChannel channel;
  final RandomAccessFile _file;

  static Future<ApplicationOwnership> acquire(Directory directory) async {
    await directory.create(recursive: true);
    final file = await File(
      p.join(directory.path, '.owner.lock'),
    ).open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive, 0, 1);
    } on FileSystemException {
      await file.close();
      throw ApplicationAlreadyRunning(directory);
    }
    try {
      return ApplicationOwnership._(
        file,
        await LocalOpenChannel.start(directory),
      );
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  Future<void> close() async {
    await channel.close();
    await _file.unlock(0, 1);
    await _file.close();
  }
}

final class ApplicationAlreadyRunning implements Exception {
  const ApplicationAlreadyRunning([this.directory]);
  final Directory? directory;
}
