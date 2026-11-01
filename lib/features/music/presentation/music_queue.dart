import 'package:flutter/material.dart';
import '../application/music_controller.dart';
import 'music_actions.dart';

Future<void> showMusicQueue(BuildContext context, MusicController controller) =>
    showDialog<void>(
      context: context,
      builder: (_) => _MusicQueue(controller: controller),
    );

final class _MusicQueue extends StatelessWidget {
  const _MusicQueue({required this.controller});
  final MusicController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => AlertDialog(
      title: Text('播放队列 · ${controller.queue.length} 首'),
      content: SizedBox(
        width: 640,
        height: 460,
        child: controller.queue.isEmpty
            ? const Center(child: Text('播放队列为空。'))
            : ListView.builder(
                itemCount: controller.queue.length,
                itemBuilder: (context, index) => _row(context, index),
              ),
      ),
      actions: [
        TextButton(
          onPressed: controller.queue.length > 1
              ? controller.clearUpcoming
              : null,
          child: const Text('清空其他歌曲'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  Widget _row(BuildContext context, int index) {
    final track = controller.queue[index];
    final current = controller.index == index;
    return ListTile(
      key: ValueKey('music-queue-${track.key}'),
      selected: current,
      leading: Icon(current ? Icons.equalizer : Icons.music_note_outlined),
      title: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => controller.select(controller.queue, index),
      trailing: PopupMenuButton<String>(
        tooltip: '队列歌曲操作',
        onSelected: (action) => musicAction(context, () async {
          if (action == 'remove') {
            await controller.removeFromQueue(track.key);
          } else {
            controller.moveInQueue(track.key, action == 'up' ? -1 : 1);
          }
        }),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'up',
            enabled: index > 0,
            child: const Text('上移'),
          ),
          PopupMenuItem(
            value: 'down',
            enabled: index + 1 < controller.queue.length,
            child: const Text('下移'),
          ),
          PopupMenuItem(
            value: 'remove',
            child: Text(current ? '移出当前歌曲并继续播放' : '移出队列'),
          ),
        ],
      ),
    );
  }
}
