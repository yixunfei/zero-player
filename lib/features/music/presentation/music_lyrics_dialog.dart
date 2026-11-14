import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../application/music_controller.dart';

Future<void> showMusicLyrics(
  BuildContext context,
  MusicController controller,
) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _MusicLyricsPage(controller: controller),
  ),
);

final class _MusicLyricsPage extends StatefulWidget {
  const _MusicLyricsPage({required this.controller});
  final MusicController controller;

  @override
  State<_MusicLyricsPage> createState() => _MusicLyricsPageState();
}

final class _MusicLyricsPageState extends State<_MusicLyricsPage> {
  final _scroll = ScrollController();
  Object? _lastLine;
  DateTime? _manualScrollUntil;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final track = controller.selected;
      final lines = controller.lyrics.lines;
      final current = controller.lyrics.indexAt(controller.snapshot.position);
      final extent = MediaQuery.textScalerOf(context).scale(76);
      final line = (controller.lyrics, current, extent);
      if (_lastLine != line) {
        _lastLine = line;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              _lastLine != line ||
              !_scroll.hasClients ||
              (_manualScrollUntil?.isAfter(DateTime.now()) ?? false)) {
            return;
          }
          _scroll.jumpTo(
            (current * extent).clamp(0.0, _scroll.position.maxScrollExtent),
          );
        });
      }
      return Scaffold(
        appBar: AppBar(title: const Text('同步歌词')),
        body: SafeArea(
          child: Column(
            children: [
              if (track != null)
                ListTile(
                  title: Text(track.title),
                  subtitle: Text(track.artist),
                ),
              Expanded(
                child: lines.isEmpty
                    ? Center(
                        child: Text(
                          controller.lyricsLoading ? '正在获取歌词…' : '暂无可显示的同步歌词',
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final margin = ((constraints.maxHeight - extent) / 2)
                              .clamp(0.0, double.infinity);
                          return NotificationListener<UserScrollNotification>(
                            onNotification: (notification) {
                              if (notification.direction !=
                                  ScrollDirection.idle) {
                                _manualScrollUntil = DateTime.now().add(
                                  const Duration(seconds: 5),
                                );
                              }
                              return false;
                            },
                            child: ListView.builder(
                              controller: _scroll,
                              itemCount: lines.length,
                              itemExtent: extent,
                              padding: EdgeInsets.symmetric(
                                vertical: margin,
                                horizontal: 24,
                              ),
                              itemBuilder: (context, index) {
                                final lyric = lines[index];
                                return TextButton(
                                  onPressed: () => controller.seek(lyric.time),
                                  child: Text(
                                    [lyric.text, lyric.translation]
                                        .where((text) => text.isNotEmpty)
                                        .join('\n'),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: index == current
                                        ? Theme.of(
                                            context,
                                          ).textTheme.titleMedium
                                        : Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '上一首',
                    onPressed: controller.previous,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  IconButton(
                    tooltip: controller.playing ? '暂停音乐' : '播放音乐',
                    onPressed: controller.loading ? null : controller.toggle,
                    icon: Icon(
                      controller.playing ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    tooltip: '下一首',
                    onPressed: controller.hasNext ? controller.next : null,
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
