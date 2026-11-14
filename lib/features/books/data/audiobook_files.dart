import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../media/gateway/offline_server.dart';
import '../../downloads/application/mp4_download.dart';
import '../domain/book.dart';
import 'audiobook_format.dart';
import 'book_client.dart';

export 'audiobook_format.dart';

final class AudiobookFiles {
  AudiobookFiles(this.root, this.client, this.offline, this.validate);
  final Directory root;
  final BookClient client;
  final OfflineServer offline;
  final Future<void> Function(File, CancellationToken, String) validate;
  Future<void> _writeQueue = Future.value();
  final _running = <CancellationToken>{};
  bool _closed = false;

  Directory _directory(Book book, BookChapter chapter) =>
      Directory(p.join(root.path, '${book.id}-${chapter.id}'));
  Future<String?> _entry(Directory dir) async {
    final index = File(p.join(dir.path, 'entry'));
    if (!await index.exists()) return null;
    final name = await index.readAsString();
    return RegExp(r'^audio\.(mp3|wav|ogg|flac|m4a|aac)$').hasMatch(name) &&
            await File(p.join(dir.path, name)).exists()
        ? name
        : null;
  }

  Future<bool> contains(Book book, BookChapter chapter) async =>
      await _entry(_directory(book, chapter)) != null;

  Future<Set<String>> saved(Book book) async {
    if (!await root.exists()) return {};
    final prefix = '${book.id}-';
    final result = <String>{};
    await for (final entity in root.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory &&
          name.startsWith(prefix) &&
          await _entry(entity) != null) {
        result.add(name.substring(prefix.length));
      }
    }
    return result;
  }

  Future<OfflineSession> open(Book book, BookChapter chapter) async {
    final dir = _directory(book, chapter);
    final entry = await _entry(dir);
    if (entry == null) throw const FormatException('该章节尚未下载');
    return offline.open('books:${book.id}:${chapter.id}', dir, entry);
  }

  Future<void> download(
    BookSource source,
    Book book,
    BookChapter chapter,
    CancellationToken token,
    void Function() authorize, {
    BookChapter? targetChapter,
  }) {
    if (_closed) throw StateError('音频存储已关闭');
    final operation = _writeQueue.then(
      (_) => _download(
        source,
        book,
        chapter,
        targetChapter ?? chapter,
        token,
        authorize,
      ),
    );
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _download(
    BookSource source,
    Book book,
    BookChapter chapter,
    BookChapter targetChapter,
    CancellationToken token,
    void Function() authorize,
  ) async {
    if (_closed) throw StateError('音频存储已关闭');
    token.check();
    authorize();
    if (await contains(book, targetChapter)) return;
    // close() may run while the filesystem check is pending.
    if (_closed) throw StateError('音频存储已关闭');
    token.check();
    authorize();
    _running.add(token);
    Directory? staging;
    try {
      final uri = await client.audio(source, chapter, token, book: book);
      authorize();
      await root.create(recursive: true);
      final budget = await _downloadBudget();
      staging = await root.createTemp('.pending-');
      final transfer = CancellationToken();
      final unlink = token.listen(transfer.cancel);
      final deadline = Timer(const Duration(minutes: 2), transfer.cancel);
      late String name;
      try {
        for (var attempt = 0; ; attempt++) {
          try {
            await downloadMp4(
              uri: uri,
              directory: staging,
              http: client.network.http,
              policy: HeaderPolicy({uri: const {}}),
              cancellation: transfer,
              maxBytes: budget,
              validateTarget: (target) {
                authorize();
                source.requestTarget(target, media: true);
              },
              progress: (_, _, _) async => authorize(),
              validate: (file, cancellation) async {
                final head = await file
                    .openRead(0, 64)
                    .expand((chunk) => chunk)
                    .toList();
                final extension = audiobookExtension(
                  head,
                  isM4b: uri.path.toLowerCase().endsWith('.m4b'),
                );
                name = 'audio.$extension';
                authorize();
                await validate(file, cancellation, extension);
              },
              fileName: 'audio.download',
            );
            break;
          } on Exception catch (error) {
            if (attempt >= 2 ||
                transfer.isCancelled ||
                !(error is SocketException ||
                    error is HttpException ||
                    error is TimeoutException)) {
              rethrow;
            }
          }
        }
      } on RequestCancelled {
        token.check();
        throw const FormatException('听书下载超时，请重试');
      } finally {
        deadline.cancel();
        unlink();
      }
      await File(
        p.join(staging.path, 'audio.download'),
      ).rename(p.join(staging.path, name));
      await File(p.join(staging.path, 'mp4-state.json')).delete();
      await File(
        p.join(staging.path, 'entry'),
      ).writeAsString(name, flush: true);
      token.check();
      authorize();
      final target = _directory(book, targetChapter);
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);
      staging = null;
    } finally {
      _running.remove(token);
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<int> _downloadBudget() async {
    var size = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) size += await entity.length();
    }
    final budget = (512 * 1024 * 1024 - size).clamp(0, 96 * 1024 * 1024);
    if (budget <= 0) throw const FormatException('听书离线空间已满');
    return budget;
  }

  Future<void> remove(Book book, BookChapter chapter) {
    final operation = _writeQueue.then((_) async {
      if (offline.isPlaying('books:${book.id}:${chapter.id}')) {
        throw const FormatException('请先关闭正在播放的章节');
      }
      final dir = _directory(book, chapter);
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> removeSaved(Book book) async {
    final ids = await saved(book);
    final operation = _writeQueue.then((_) async {
      for (final id in ids) {
        if (offline.isPlaying('books:${book.id}:$id')) {
          throw const FormatException('请先关闭正在播放的章节');
        }
      }
      for (final id in ids) {
        final dir = Directory(p.join(root.path, '${book.id}-$id'));
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    await operation;
  }

  Future<void> close() async {
    _closed = true;
    for (final token in _running.toList()) {
      token.cancel();
    }
    await _writeQueue;
  }
}
