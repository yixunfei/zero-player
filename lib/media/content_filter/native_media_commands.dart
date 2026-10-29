import 'dart:async';
import 'dart:convert';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import '../../core/network/cancellation_token.dart';
import 'filter_types.dart';

final class NativeMediaCommands {
  static const hlsOptions = [
    '-allowed_extensions',
    'ALL',
    '-allowed_segment_extensions',
    'ALL',
    '-extension_picky',
    '0',
    // The sampler owns lookahead. FFmpeg's extra connection otherwise fetches
    // an interior ad segment even when its sampling request was omitted.
    '-http_multiple',
    '0',
  ];
  Future<void> run(List<String> arguments, CancellationToken token) async {
    token.check();
    final done = Completer<FFmpegSession>();
    final session = await FFmpegKit.executeWithArgumentsAsync([
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostdin',
      '-y',
      ...arguments,
    ], (result) => done.complete(result));
    final remove = token.listen(
      () => unawaited(FFmpegKit.cancel(session.getSessionId())),
    );
    try {
      final result = await done.future.timeout(const Duration(seconds: 60));
      token.check();
      if (!ReturnCode.isSuccess(await result.getReturnCode())) {
        throw const FilterFailure('媒体采样失败，请重试、改用画面或仅保存本集区间');
      }
    } on TimeoutException {
      await FFmpegKit.cancel(session.getSessionId());
      await done.future;
      throw const FilterFailure('媒体采样超时，已取消本次采集');
    } finally {
      remove();
    }
  }

  Future<Map<String, dynamic>> probe(
    String input,
    String protocols,
    CancellationToken token, {
    bool hls = false,
  }) async {
    token.check();
    final done = Completer<FFprobeSession>();
    final session = await FFprobeKit.executeWithArgumentsAsync([
      '-hide_banner',
      '-v',
      'error',
      '-protocol_whitelist',
      protocols,
      '-format_whitelist',
      'hls,mov,flv,mpegts',
      if (hls) ...hlsOptions,
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      '-i',
      input,
    ], (result) => done.complete(result));
    final remove = token.listen(
      () => unawaited(FFmpegKit.cancel(session.getSessionId())),
    );
    try {
      final result = await done.future.timeout(const Duration(seconds: 30));
      token.check();
      if (!ReturnCode.isSuccess(await result.getReturnCode())) {
        throw const FilterFailure('无法读取媒体信息，严格过滤已停止播放');
      }
      return jsonDecode(await result.getOutput() ?? '') as Map<String, dynamic>;
    } on TimeoutException {
      await FFmpegKit.cancel(session.getSessionId());
      await done.future;
      throw const FilterFailure('媒体信息读取超时，已停止播放');
    } finally {
      remove();
    }
  }
}
