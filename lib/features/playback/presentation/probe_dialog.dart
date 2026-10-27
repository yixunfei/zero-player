import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../media/network/media_probe.dart';
import '../application/playback_controller.dart';

Future<void> showMediaProbe(
  BuildContext context,
  AppServices services,
  PlaybackController player,
  String decodedResolution,
) => perform(context, () async {
  final request = player.request;
  if (request == null || request.offline != null) return;
  final uri = player.resolvedMedia?.uri ?? player.episode.uri;
  final source = await services.sources.find(request.item.sourceId);
  final token = CancellationToken();
  final work = probeMedia(
    services.http,
    uri,
    HeaderPolicy({
      uri:
          player.resolvedMedia?.headers ??
          request.headersByUri[uri] ??
          (request.headers.isNotEmpty
              ? request.headers
              : source?.headers ?? {}),
    }),
    token,
    networkTimeout: const Duration(seconds: 10),
  );
  if (!context.mounted) {
    token.cancel();
    return;
  }
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('媒体测速与画质'),
        content: SizedBox(
          width: 460,
          height: 230,
          child: FutureBuilder(
            future: work,
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('探测未完成，可稍后重试。播放状态不受影响。');
              final result = snapshot.data;
              if (result == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return Text(
                '首包：${result.firstByte.inMilliseconds} ms\n'
                '样本吞吐：${result.kibPerSecond.toStringAsFixed(0)} KiB/s\n'
                '读取样本：${(result.bytes / 1024).toStringAsFixed(0)} KiB\n'
                '清单声明分辨率：${result.resolution ?? '未声明'}\n'
                '当前解码分辨率：$decodedResolution\n\n'
                '响应速度不代表画质；单次探测最多 2 MiB、10 秒网络时间（不含排队）。',
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              token.cancel();
              Navigator.pop(context);
            },
            child: const Text('停止 / 关闭'),
          ),
        ],
      ),
    );
  } finally {
    token.cancel();
    try {
      await work;
    } catch (_) {}
  }
});
