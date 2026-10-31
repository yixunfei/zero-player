export 'video_file_types.dart';
import 'video_file_types.dart';
import 'dart:async';
import 'package:crypto/crypto.dart';
import '../network/cancellation_token.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'publish_file.dart';

final class VideoFiles {
  static const channel = MethodChannel('zero_player/platform');
  static const _progress = MethodChannel('zero_player/local_video_progress');

  static Future<String?> chooseDirectory() => Platform.isAndroid
      ? channel.invokeMethod<String>('chooseVideoDirectory')
      : getDirectoryPath(confirmButtonText: '保存到此目录');

  static Future<XFile?> chooseVideo({
    int? maxBytes,
    void Function(String identity)? onIdentity,
    void Function(int copied, int total)? onProgress,
    CancellationToken? cancellation,
  }) async {
    if (Platform.isAndroid) {
      cancellation?.check();
      _progress.setMethodCallHandler((call) async {
        if (call.method == 'progress') {
          final data = Map<String, dynamic>.from(call.arguments as Map);
          onProgress?.call(data['copied'] as int, data['total'] as int);
        }
      });
      final remove = cancellation?.listen(
        () => unawaited(channel.invokeMethod<void>('cancelLocalVideo')),
      );
      try {
        final selected = await channel.invokeMapMethod<String, dynamic>(
          'chooseLocalVideo',
          {'maxBytes': maxBytes},
        );
        if (selected == null) return null;
        onIdentity?.call(selected['identity'] as String);
        return XFile(selected['path'] as String);
      } finally {
        remove?.call();
        _progress.setMethodCallHandler(null);
      }
    }
    return openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '视频',
          extensions: videoExtensions,
          mimeTypes: ['video/*'],
        ),
      ],
    );
  }

  static Future<void> clearLocalCopies(Iterable<String> protectedPaths) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('clearLocalVideoCopies', {
        'protected': protectedPaths.toList(),
      });
    }
  }

  static Future<String?> recoverSave(
    String destination,
    String name,
    String digest,
  ) async {
    if (Platform.isAndroid) {
      return channel.invokeMethod<String>('verifyVideoInDirectory', {
        'directory': destination,
        'name': name,
        'digest': digest,
      });
    }
    final file = File(p.join(destination, name));
    if (!await file.exists()) return null;
    if ('${await sha256.bind(file.openRead()).first}' != digest) {
      throw const FileSystemException('目标内容与保存意图不一致，请选择其他目录');
    }
    return file.path;
  }

  static Future<String> save(
    File source,
    String destination,
    String name, {
    CancellationToken? cancellation,
  }) async {
    cancellation?.check();
    if (Platform.isAndroid) {
      final saving = channel.invokeMethod<String>('saveVideoToDirectory', {
        'path': source.path,
        'directory': destination,
        'name': name,
      });
      final remove = cancellation?.listen(
        () => unawaited(
          channel.invokeMethod<void>('cancelVideoSave', {'path': source.path}),
        ),
      );
      try {
        return (await saving)!;
      } finally {
        remove?.call();
      }
    }
    final target = File(p.join(destination, name));
    // Task-specific names avoid collisions; existing files are preserved.
    if (await target.exists()) {
      throw const FileSystemException('目标文件已存在，请选择其他目录');
    }
    final temporary = File(
      '${target.path}.part-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      final sink = await temporary.open(mode: FileMode.write);
      try {
        await for (final chunk in source.openRead()) {
          cancellation?.check();
          await sink.writeFrom(chunk);
        }
      } finally {
        await sink.close();
      }
      cancellation?.check();
      if (await target.exists()) {
        throw const FileSystemException('目标文件已存在');
      }
      await publishFile(temporary, target);
      return target.path;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }
}
