import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../../core/platform/video_files.dart';
import '../../../core/network/cancellation_token.dart';
import '../application/local_video.dart';
import '../data/local_video_repository.dart';

final class LocalVideoPage extends StatefulWidget {
  const LocalVideoPage({super.key, required this.services, this.path, this.id});
  final AppServices services;
  final String? path;
  final String? id;
  @override
  State<LocalVideoPage> createState() => _LocalVideoPageState();
}

final class _LocalVideoPageState extends State<LocalVideoPage> {
  bool busy = false;
  String? _documentIdentity;
  bool _missing = false;
  @override
  void initState() {
    super.initState();
    if (widget.path != null || widget.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitial());
    }
  }

  @override
  void didUpdateWidget(covariant LocalVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path || widget.id != oldWidget.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitial());
    }
  }

  Future<void> _openInitial() => _open(initial: true);

  Future<void> _open({bool initial = false, bool relocate = false}) async {
    if (busy || !mounted) return;
    setState(() => busy = true);
    await perform(context, () async {
      var path = initial ? widget.path : null;
      if (initial && path == null && widget.id != null) {
        path = await LocalVideoRepository(
          widget.services.db,
        ).pathFor(widget.id!);
        if (path == null || !await File(path).exists()) _missing = true;
        if (_missing) throw const FormatException('本地视频记录失效，请重新选择文件');
      }
      final selected = path ?? await _chooseVideo();
      if (selected == null || !mounted) return;
      final request = await LocalVideo.open(
        widget.services,
        selected,
        previousId: initial || relocate ? widget.id : null,
        documentIdentity: _documentIdentity,
      );
      _missing = false;
      if (!mounted) {
        request.offline?.close();
        return;
      }
      await context.push('/player', extra: request);
    });
    if (mounted) setState(() => busy = false);
  }

  Future<String?> _chooseVideo() async {
    _documentIdentity = null;
    if (!Platform.isAndroid) return (await VideoFiles.chooseVideo())?.path;
    final token = CancellationToken();
    final progress = ValueNotifier<(int, int)>((0, -1));
    BuildContext? dialog;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          dialog = context;
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('选择并复制本地视频'),
              content: ValueListenableBuilder<(int, int)>(
                valueListenable: progress,
                builder: (_, value, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: value.$2 > 0
                          ? (value.$1 / value.$2).clamp(0.0, 1.0)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      value.$1 == 0
                          ? '请选择视频文件'
                          : '已复制 ${(value.$1 / 1048576).toStringAsFixed(1)} MiB${value.$2 > 0 ? ' / ${(value.$2 / 1048576).toStringAsFixed(1)} MiB' : ''}',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: token.cancel, child: const Text('取消复制')),
              ],
            ),
          );
        },
      ),
    );
    try {
      return (await VideoFiles.chooseVideo(
        maxBytes: widget.services.settings.value.downloadMiB * 1024 * 1024,
        cancellation: token,
        onIdentity: (identity) => _documentIdentity = identity,
        onProgress: (copied, total) => progress.value = (copied, total),
      ))?.path;
    } finally {
      if (dialog != null && dialog!.mounted) Navigator.pop(dialog!);
      progress.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_file_outlined, size: 64),
          const SizedBox(height: 16),
          Text('播放本地视频', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text(
            '支持 MP4、MKV、AVI、MOV、WebM、TS 等常见视频格式。\n保留播放进度，支持倍速、快进、全屏和截图。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_missing && widget.id != null)
            TextButton(
              onPressed: busy ? null : () => _open(relocate: true),
              child: const Text('重新定位原记录（保留进度）'),
            ),
          FilledButton.icon(
            onPressed: busy ? null : () => _open(),
            icon: const Icon(Icons.folder_open),
            label: Text(busy ? '正在打开…' : '选择视频文件'),
          ),
        ],
      ),
    ),
  );
}
