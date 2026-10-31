import 'package:flutter/material.dart';
import '../../../app/widgets.dart';
import '../application/playback_controller.dart';
import 'timeline_slider.dart';

final class PlayerTransport extends StatelessWidget {
  const PlayerTransport({
    super.key,
    required this.controller,
    required this.fullscreen,
    required this.onFullscreen,
    required this.onOptions,
    required this.onMark,
    required this.onScreenshot,
    required this.onFit,
    required this.fit,
  });
  final PlaybackController controller;
  final bool fullscreen;
  final BoxFit fit;
  final VoidCallback onFullscreen, onOptions, onMark, onScreenshot;
  final ValueChanged<BoxFit> onFit;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!controller.isLive)
        TimelineSlider(
          position: controller.originalPosition,
          duration: controller.originalDuration,
          buffer: controller.originalBuffer,
          marks: controller.marks,
          seek: controller.seek,
        ),
      if (controller.canUndoSkip)
        Row(
          children: [
            Expanded(
              child: Text(
                controller.notice ?? '已跳过标记内容',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: controller.undoSkip,
              child: const Text('撤销跳过'),
            ),
          ],
        ),
      _toolbar(),
    ],
  );

  Widget _toolbar() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        IconButton.filledTonal(
          tooltip: controller.state.playing ? '暂停 (空格)' : '播放 (空格)',
          onPressed: controller.busy ? null : controller.toggle,
          icon: Icon(controller.state.playing ? Icons.pause : Icons.play_arrow),
        ),
        _rate(),
        if (!controller.isLive)
          IconButton(
            tooltip: controller.request?.supportsMarks == true
                ? '标记不良信息 · 最近 4 秒'
                : '本地和下载视频暂不支持特征标记',
            onPressed:
                controller.request?.supportsMarks != true ||
                    controller.busy ||
                    controller.originalPosition < const Duration(seconds: 1)
                ? null
                : onMark,
            icon: const Icon(Icons.flag_outlined),
          ),
        IconButton(
          tooltip: fullscreen ? '退出全屏 (F)' : '全屏 (F)',
          onPressed: onFullscreen,
          icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
        ),
        IconButton(
          tooltip: '选集与设置',
          onPressed: onOptions,
          icon: const Icon(Icons.tune),
        ),
        if (!controller.isLive) ...[
          IconButton(
            tooltip: '后退 10 秒 (←)',
            onPressed: () => controller.seek(
              controller.originalPosition - const Duration(seconds: 10),
            ),
            icon: const Icon(Icons.replay_10),
          ),
          IconButton(
            tooltip: '前进 10 秒 (→)',
            onPressed: () => controller.seek(
              controller.originalPosition + const Duration(seconds: 10),
            ),
            icon: const Icon(Icons.forward_10),
          ),
        ],
        _volume(),
        PopupMenuButton<BoxFit>(
          tooltip: '画面比例',
          onSelected: onFit,
          initialValue: fit,
          icon: const Icon(Icons.aspect_ratio),
          itemBuilder: (_) => const [
            PopupMenuItem(value: BoxFit.contain, child: Text('适应 · 保留完整画面')),
            PopupMenuItem(value: BoxFit.cover, child: Text('填充 · 裁切边缘')),
            PopupMenuItem(value: BoxFit.fill, child: Text('拉伸 · 铺满屏幕')),
          ],
        ),
        IconButton(
          tooltip: '截取当前帧 ${clockText(controller.originalPosition)}',
          onPressed: onScreenshot,
          icon: const Icon(Icons.photo_camera_outlined),
        ),
        IconButton(
          tooltip: '下一集 / 频道',
          onPressed: controller.request == null ? null : controller.nextEpisode,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    ),
  );

  Widget _rate() => PopupMenuButton<double>(
    tooltip: '播放速率',
    initialValue: controller.state.rate,
    onSelected: controller.engine.setRate,
    itemBuilder: (_) => [
      for (final rate in [.5, .75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0])
        PopupMenuItem(value: rate, child: Text('$rate×')),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text('${controller.state.rate}×'),
    ),
  );

  Widget _volume() => SizedBox(
    width: 150,
    child: Row(
      children: [
        IconButton(
          tooltip: controller.state.volume == 0 ? '取消静音' : '静音',
          onPressed: () => controller.engine.setVolume(
            controller.state.volume == 0 ? 60 : 0,
          ),
          icon: Icon(
            controller.state.volume == 0 ? Icons.volume_off : Icons.volume_up,
          ),
        ),
        Expanded(
          child: Slider(
            value: controller.state.volume.clamp(0, 100),
            max: 100,
            semanticFormatterCallback: (value) => '音量 ${value.round()}%',
            onChanged: controller.engine.setVolume,
          ),
        ),
      ],
    ),
  );
}
