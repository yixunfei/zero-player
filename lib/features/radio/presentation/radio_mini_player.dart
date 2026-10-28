import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../application/radio_controller.dart';

final class RadioMiniPlayer extends StatelessWidget {
  const RadioMiniPlayer({super.key, required this.controller});
  final RadioController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => !controller.active
        ? const SizedBox.shrink()
        : Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: SafeArea(
              top: false,
              bottom: false,
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.radio_outlined),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => context.go('/radio'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              controller.selected!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              controller.error ??
                                  (controller.loading
                                      ? '连接中'
                                      : controller.playing
                                      ? '后台收听中'
                                      : '已暂停'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: controller.playing ? '暂停广播' : '播放广播',
                    onPressed: controller.loading ? null : controller.toggle,
                    icon: Icon(
                      controller.playing ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    tooltip: '停止广播',
                    onPressed: controller.stop,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
  );
}
