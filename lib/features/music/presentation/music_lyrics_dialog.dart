import 'package:flutter/material.dart';
import '../application/music_controller.dart';

Future<void> showMusicLyrics(
  BuildContext context,
  MusicController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final track = controller.selected;
      final lines = controller.lyrics.lines;
      final current = controller.lyrics.indexAt(controller.snapshot.position);
      final start = (current - 2).clamp(0, lines.length);
      final end = (current + 3).clamp(start, lines.length);
      return AlertDialog(
        scrollable: true,
        title: const Text('同步歌词'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (track != null)
                Text(
                  track.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              if (lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    controller.lyricsLoading ? '正在获取歌词…' : '暂无可显示的同步歌词',
                  ),
                ),
              for (var i = start; i < end; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    [
                      lines[i].text,
                      lines[i].translation,
                    ].where((text) => text.isNotEmpty).join('\n'),
                    style: i == current
                        ? Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  ),
);
