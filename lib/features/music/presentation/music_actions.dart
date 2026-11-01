import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../domain/music_track.dart';

Future<void> musicAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error is FormatException ? error.message : '操作失败，请重试。'),
        ),
      );
    }
  }
}

Future<String?> musicName(
  BuildContext context,
  String title, {
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _MusicName(title: title, initial: initial),
);

final class _MusicName extends StatefulWidget {
  const _MusicName({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_MusicName> createState() => _MusicNameState();
}

final class _MusicNameState extends State<_MusicName> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: '歌单名称'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('保存'),
      ),
    ],
  );
}

Future<void> addToMusicPlaylist(
  BuildContext context,
  AppServices services,
  MusicTrack track,
) async {
  await services.musicLibrary.load();
  if (!context.mounted) return;
  final selected = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('加入歌单'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'new'),
          child: const Text('新建歌单'),
        ),
        for (final list in services.musicLibrary.playlists)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, list.id),
            child: Text(list.name),
          ),
      ],
    ),
  );
  if (selected == null || !context.mounted) return;
  var id = selected;
  if (id == 'new') {
    final name = await musicName(context, '新建歌单');
    if (name == null) return;
    id = await services.musicLibrary.create(name);
  }
  await services.musicLibrary.add(id, track);
}

final class MusicTrackMenu extends StatelessWidget {
  const MusicTrackMenu({
    super.key,
    required this.services,
    required this.track,
  });
  final AppServices services;
  final MusicTrack track;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '歌曲操作',
    onSelected: (value) => musicAction(
      context,
      () => switch (value) {
        'playlist' => addToMusicPlaylist(context, services, track),
        'next' => services.musicPlayer.enqueue(track, playNext: true),
        'queue' => services.musicPlayer.enqueue(track),
        _ => services.musicDownloads.download(track),
      },
    ),
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'playlist', child: Text('加入歌单')),
      const PopupMenuItem(value: 'next', child: Text('下一首播放')),
      const PopupMenuItem(value: 'queue', child: Text('加入播放队列')),
      PopupMenuItem(
        value: 'download',
        enabled: track.canDownload,
        child: const Text('下载离线'),
      ),
    ],
  );
}
