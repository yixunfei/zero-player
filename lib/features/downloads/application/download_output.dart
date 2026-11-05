import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../../../core/network/cancellation_token.dart';
import '../../../core/platform/video_files.dart';
import '../../../media/export/media_exporter.dart';
import '../../../media/gateway/offline_server.dart';
import '../data/download_repository.dart';
import '../domain/download_task.dart';

final _activeOutputs = <String>{};

Future<void> saveDownloadOutput(
  DownloadTask task,
  DownloadRepository repository,
  OfflineServer offline,
  MediaExporter exporter,
  CancellationToken token,
) async {
  final destination = await repository.output(task.id);
  if (destination == null) return;
  if (!repository.ownsPath(task.directory)) throw StateError('任务路径不属于下载目录');
  final directory = Directory(task.directory);
  final key = directory.absolute.path;
  if (!_activeOutputs.add(key)) throw StateError('此任务正在保存');
  Directory? work;
  OfflineSession? session;
  try {
    repository.requireAllowed(task);
    final journalKey = 'download_publish:${task.id}';
    if (await _recoverOutput(
      task,
      repository,
      destination,
      journalKey,
      token,
    )) {
      return;
    }
    await _cleanInterruptedOutput(directory, task.localPath!);
    token.check();
    work = await directory.createTemp('.save-');
    final temporary = File(p.join(work.path, 'output.mp4'));
    session = await offline.open(task.id, directory, task.localPath!);
    await repository.status(task.id, DownloadStatus.saving, error: '正在保存到所选目录');
    await exporter.export(
      session.uri,
      temporary.path,
      ExportFormat.mp4,
      cancellation: token,
    );
    token.check();
    repository.requireAllowed(task);
    var title = task.title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    if (title.length > 80) title = title.substring(0, 80);
    final nonce = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final name = '$title-${task.id}-$nonce.mp4';
    final digest = '${await sha256.bind(temporary.openRead()).first}';
    await repository.db.write(
      'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
      [
        journalKey,
        jsonEncode({
          'destination': destination,
          'name': name,
          'digest': digest,
        }),
      ],
    );
    token.check();
    final saved = await VideoFiles.save(
      temporary,
      destination,
      name,
      cancellation: token,
    );
    // Once published, record the result even if cancellation arrives concurrently.
    await repository.saved(task.id, saved);
  } on RequestCancelled {
    rethrow;
  } catch (error) {
    throw FileSystemException('保存到所选目录失败，请检查空间和授权后重试：$error');
  } finally {
    session?.close();
    try {
      if (work != null && await work.exists()) {
        await work.delete(recursive: true);
      }
    } finally {
      _activeOutputs.remove(key);
    }
  }
}

Future<bool> _recoverOutput(
  DownloadTask task,
  DownloadRepository repository,
  String destination,
  String journalKey,
  CancellationToken token,
) async {
  final entries = await repository.db.rows(
    'SELECT value FROM app_meta WHERE key=?',
    [journalKey],
  );
  try {
    if (entries.isNotEmpty) {
      final intent = jsonDecode(entries.single['value'] as String);
      if (intent is! Map ||
          intent['name'] is! String ||
          intent['digest'] is! String) {
        throw const FormatException('保存记录已损坏');
      }
      if (intent['destination'] == destination) {
        token.check();
        final recovered = await VideoFiles.recoverSave(
          destination,
          intent['name'] as String,
          intent['digest'] as String,
        );
        if (recovered != null) {
          await repository.saved(task.id, recovered);
          return true;
        }
      }
    }
  } on FormatException {
    await repository.db.write('DELETE FROM app_meta WHERE key=?', [journalKey]);
  } on FileSystemException {
    await repository.db.write('DELETE FROM app_meta WHERE key=?', [journalKey]);
  }
  return false;
}

Future<void> _cleanInterruptedOutput(Directory directory, String entry) async {
  await for (final entity in directory.list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (entity is Directory && name.startsWith('.save-')) {
      await entity.delete(recursive: true);
    } else if (entity is File && name == 'output.mp4' && name != entry) {
      await entity.delete();
    }
  }
}
