import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../application/music_controller.dart';
import '../data/music_library.dart';
import 'music_queue.dart';
import 'music_actions.dart';

String musicTime(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

final class MusicPlayer extends StatelessWidget {
  const MusicPlayer({
    super.key,
    required this.controller,
    this.compact = false,
  });
  final MusicController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final track = controller.selected;
      if (track == null) return const SizedBox.shrink();
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_header(context), if (!compact) _timeline(context)],
          ),
        ),
      );
    },
  );

  Widget _header(BuildContext context) {
    final track = controller.selected!;
    final metadata = ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        controller.error ??
            (controller.loading
                ? '连接中…'
                : '${track.artist} · ${controller.snapshot.completed
                      ? '已播完'
                      : controller.snapshot.buffering
                      ? '缓冲中…'
                      : controller.playing
                      ? '正在播放'
                      : '已暂停'}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: compact ? () => context.go('/music') : null,
    );
    final controls = <Widget>[
      if (!compact)
        IconButton(
          tooltip: '上一首',
          onPressed: controller.previous,
          icon: const Icon(Icons.skip_previous),
        ),
      IconButton(
        tooltip: controller.playing ? '暂停音乐' : '播放音乐',
        onPressed: controller.loading ? null : controller.toggle,
        icon: controller.loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(controller.playing ? Icons.pause : Icons.play_arrow),
      ),
      IconButton(
        tooltip: '下一首',
        onPressed: controller.hasNext ? controller.next : null,
        icon: const Icon(Icons.skip_next),
      ),
      IconButton(
        tooltip: '播放队列（${controller.queue.length} 首）',
        onPressed: () => showMusicQueue(context, controller),
        icon: const Icon(Icons.queue_music),
      ),
      IconButton(
        tooltip: '停止音乐',
        onPressed: controller.stop,
        icon: const Icon(Icons.close),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              metadata,
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: controls,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: metadata),
            ...controls,
          ],
        );
      },
    );
  }

  Widget _timeline(BuildContext context) {
    final state = controller.snapshot;
    final progress = <Widget>[
      Text(musicTime(state.position)),
      Expanded(
        child: _MusicSeekBar(
          key: ValueKey(controller.selected?.key),
          controller: controller,
        ),
      ),
      Text(musicTime(state.duration)),
    ];
    final actions = <Widget>[
      PopupMenuButton<MusicPlayMode>(
        tooltip: '播放模式：${musicModeLabels[controller.mode.index]}',
        icon: Icon(switch (controller.mode) {
          MusicPlayMode.shuffle => Icons.shuffle,
          MusicPlayMode.repeatOne => Icons.repeat_one,
          _ => Icons.repeat,
        }),
        onSelected: (mode) =>
            musicAction(context, () => controller.setMode(mode)),
        itemBuilder: (_) => [
          for (final mode in MusicPlayMode.values)
            CheckedPopupMenuItem(
              value: mode,
              checked: mode == controller.mode,
              child: Text(musicModeLabels[mode.index]),
            ),
        ],
      ),
      if (controller.error != null)
        IconButton(
          tooltip: '重新获取歌曲并重试',
          onPressed: controller.retry,
          icon: const Icon(Icons.refresh),
        ),
      PopupMenuButton<double>(
        tooltip: '音乐音量（${controller.volume.round()}%）',
        icon: const Icon(Icons.volume_up_outlined),
        onSelected: controller.setVolume,
        itemBuilder: (_) => [
          for (final value in [0.0, 25.0, 50.0, 80.0, 100.0])
            PopupMenuItem(value: value, child: Text('${value.round()}%')),
        ],
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: progress),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          );
        }
        return Row(children: [...progress, ...actions]);
      },
    );
  }
}

final class _MusicSeekBar extends StatefulWidget {
  const _MusicSeekBar({super.key, required this.controller});
  final MusicController controller;
  @override
  State<_MusicSeekBar> createState() => _MusicSeekBarState();
}

final class _MusicSeekBarState extends State<_MusicSeekBar> {
  double? _drag;
  @override
  void didUpdateWidget(_MusicSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.loading) _drag = null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final total = controller.snapshot.duration.inMilliseconds;
    final value =
        _drag ??
        (total > 0
            ? controller.snapshot.position.inMilliseconds.clamp(0, total) /
                  total
            : 0.0);
    final disabled = total <= 0 || controller.loading;
    return Slider(
      label: musicTime(Duration(milliseconds: (value * total).round())),
      value: value,
      onChanged: disabled ? null : (value) => setState(() => _drag = value),
      onChangeEnd: disabled
          ? null
          : (value) {
              setState(() => _drag = null);
              controller.seek(Duration(milliseconds: (total * value).round()));
            },
    );
  }
}
