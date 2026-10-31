import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/media_information_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

import '../../core/network/cancellation_token.dart';
import 'media_exporter.dart';

/// No shell execution or transcoding. Inputs are completed local resources or
/// capability URLs from our own loopback transport. Publishing is atomic.
final class FfmpegExporter implements MediaExporter {
  final _active = <String>{};

  Future<void> validate(File file, CancellationToken token) async {
    final session = await _execute([
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostdin',
      '-xerror',
      '-protocol_whitelist',
      'file',
      '-format_whitelist',
      'mov,mpegts',
      '-i',
      file.path,
      '-map',
      '0:v:0',
      '-map',
      '0:a:0?',
      '-f',
      'null',
      '-',
    ], token);
    token.check();
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw const FormatException('文件未通过媒体完整性检查');
    }
    final probe = await _inspectLocal(file.path);
    final info = probe.getMediaInformation();
    token.check();
    if ((double.tryParse(info?.getDuration() ?? '') ?? 0) <= 0) {
      throw const FormatException('视频时长无效');
    }
  }

  @override
  Future<ExportResult> export(
    Uri input,
    String output,
    ExportFormat format, {
    CancellationToken? cancellation,
  }) async {
    if (input.scheme != 'file' &&
        !(input.scheme == 'http' && input.host == '127.0.0.1')) {
      throw const FormatException('导出只接受已完成的本地资源');
    }
    final target = File(output).absolute;
    if (!_active.add(target.path)) throw StateError('这个目标正在导出');
    Directory? work;
    try {
      cancellation?.check();
      if (await target.exists()) throw const FileSystemException('目标文件已存在');
      await target.parent.create(recursive: true);
      work = await target.parent.createTemp('.zero-export-');
      final temporary = File('${work.path}/output.${format.name}');
      final session = await _execute([
        '-hide_banner',
        '-loglevel',
        'error',
        '-nostdin',
        '-n',
        '-protocol_whitelist',
        input.scheme == 'file' ? 'file' : 'http,tcp,crypto',
        '-format_whitelist',
        input.scheme == 'file' ? 'mov,mpegts' : 'hls,mov,mpegts',
        if (input.path.toLowerCase().endsWith('.m3u8')) ...[
          '-allowed_extensions',
          'ALL',
        ],
        '-i',
        input.scheme == 'file' ? input.toFilePath() : input.toString(),
        '-map',
        '0:v:0',
        '-map',
        '0:a:0?',
        '-c',
        'copy',
        if (format == ExportFormat.mp4) ...['-movflags', '+faststart'],
        '-f',
        format == ExportFormat.mp4 ? 'mp4' : 'mpegts',
        temporary.path,
      ], cancellation);
      cancellation?.check();
      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        throw const FormatException('此媒体无法重封装，原始下载已保留');
      }
      cancellation?.check();
      final probe = await _inspectLocal(temporary.path);
      final info = probe.getMediaInformation();
      final seconds = double.tryParse(info?.getDuration() ?? '') ?? 0;
      if (seconds <= 0 ||
          !(info?.getStreams().any((s) => s.getType() == 'video') ?? false)) {
        throw const FormatException('导出文件校验失败');
      }
      if (await target.exists()) throw const FileSystemException('目标文件已存在');
      await temporary.rename(target.path);
      return ExportResult(
        target.path,
        await target.length(),
        Duration(milliseconds: (seconds * 1000).round()),
      );
    } finally {
      _active.remove(target.path);
      if (work != null && await work.exists()) {
        await work.delete(recursive: true);
      }
    }
  }

  Future<MediaInformationSession> _inspectLocal(String path) =>
      FFprobeKit.getMediaInformationFromCommandArguments([
        '-v',
        'error',
        '-hide_banner',
        '-protocol_whitelist',
        'file',
        '-format_whitelist',
        'mov,mpegts',
        '-print_format',
        'json',
        '-show_format',
        '-show_streams',
        '-i',
        path,
      ]);

  Future<FFmpegSession> _execute(
    List<String> arguments,
    CancellationToken? token,
  ) async {
    final done = Completer<FFmpegSession>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      arguments,
      (session) => done.complete(session),
    );
    final remove = token?.listen(
      () => unawaited(FFmpegKit.cancel(session.getSessionId())),
    );
    try {
      return await done.future;
    } finally {
      remove?.call();
    }
  }
}
