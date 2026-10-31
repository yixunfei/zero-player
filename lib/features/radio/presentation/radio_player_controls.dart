import 'package:flutter/material.dart';
import '../application/radio_controller.dart';

final class RadioPlayerControls extends StatelessWidget {
  const RadioPlayerControls({
    super.key,
    required this.controller,
    this.onCollapse,
  });
  final RadioController controller;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final station = controller.selected;
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(context, station?.name),
              if (controller.error case final error?) Text(error),
              if (controller.loading || controller.buffering)
                const LinearProgressIndicator(minHeight: 2),
              Row(
                children: [
                  IconButton.filled(
                    tooltip: controller.playing ? '暂停广播' : '播放广播',
                    onPressed: station == null || controller.loading
                        ? null
                        : controller.toggle,
                    icon: Icon(
                      controller.playing ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    tooltip: '停止广播',
                    onPressed: station == null ? null : controller.stop,
                    icon: const Icon(Icons.stop),
                  ),
                  IconButton(
                    tooltip: '重新连接电台',
                    onPressed: station == null || controller.loading
                        ? null
                        : () => controller.select(
                            station,
                            lineIndex: controller.line,
                          ),
                    icon: const Icon(Icons.refresh),
                  ),
                  if (station != null && station.playbackUrls.length > 1)
                    PopupMenuButton<int>(
                      tooltip: '切换广播线路',
                      onSelected: (value) =>
                          controller.select(station, lineIndex: value),
                      itemBuilder: (_) => [
                        for (var i = 0; i < station.playbackUrls.length; i++)
                          CheckedPopupMenuItem(
                            value: i,
                            checked: i == controller.line,
                            child: Text('线路 ${i + 1}'),
                          ),
                      ],
                      icon: const Icon(Icons.alt_route),
                    ),
                  Expanded(
                    child: Slider(
                      max: 100,
                      value: controller.volume,
                      semanticFormatterCallback: (value) =>
                          '音量 ${value.round()}%',
                      onChanged: controller.setVolume,
                    ),
                  ),
                  const Icon(Icons.volume_up, size: 20),
                ],
              ),
              const Text(
                '切换页面可继续收听；Windows 播放时关闭窗口驻留托盘，右键托盘可退出。播放视频时暂停广播。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _heading(BuildContext context, String? name) => Row(
    children: [
      Expanded(
        child: Text(
          name ?? '选择电台，开始收听',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      if (onCollapse != null)
        IconButton(
          tooltip: '收起广播播放器',
          onPressed: onCollapse,
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
    ],
  );
}
