import 'package:flutter/material.dart';

import '../application/lab_controller.dart';
import 'media_input.dart';
import 'playback_panel.dart';

final class LabPage extends StatelessWidget {
  const LabPage({super.key, required this.controller});
  final LabController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ZERO / PLAYER'),
      actions: [
        IconButton(
          tooltip: '切换明暗主题',
          onPressed: controller.toggleTheme,
          icon: Icon(
            controller.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
          ),
        ),
        IconButton(
          tooltip: '切换大屏模式',
          onPressed: controller.toggleTelevision,
          icon: Icon(controller.television ? Icons.desktop_windows : Icons.tv),
        ),
        IconButton(
          tooltip: '开源许可',
          icon: const Icon(Icons.info_outline),
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Zero Player',
            applicationVersion: '0.1.0 · M0',
            applicationLegalese: 'AGPL-3.0-or-later · 媒体验证版本',
          ),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1050;
          final padding = controller.television ? 40.0 : 20.0;
          return FocusTraversalGroup(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _heading(context),
                      const SizedBox(height: 24),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: PlaybackPanel(controller: controller),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 4,
                              child: MediaInput(controller: controller),
                            ),
                          ],
                        )
                      else ...[
                        PlaybackPanel(controller: controller),
                        const SizedBox(height: 24),
                        MediaInput(controller: controller),
                      ],
                      const SizedBox(height: 24),
                      _status(context),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _heading(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'M0 / 媒体实验室',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 2,
        ),
      ),
      const SizedBox(height: 8),
      Text('先让每一帧可靠播放。', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('验证原生播放、HLS 转发与分片缓存。此版本尚未包含搜索、直播管理和离线下载。'),
    ],
  );

  Widget _status(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            controller.status,
            key: const ValueKey('playback-status'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            controller.television
                ? '大屏模式 · 使用方向键移动焦点，确认键操作；播放区支持空格与左右键。'
                : '支持 HTTP(S) MP4、HLS 和 HTTP-FLV。网关实验缓存上限 256 MiB，单资源上限 64 MiB。',
          ),
          const SizedBox(height: 8),
          const Text('测试样本由本机开发工具生成；真实来源可用性和真机兼容性需另行验证。'),
        ],
      ),
    ),
  );
}
