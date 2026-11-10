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

Future<String?> musicPlaylistLink(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const _MusicName(
    title: '导入网易云公开歌单',
    initial: '',
    label: '歌单链接或数字 ID',
    maxLength: 500,
    submit: '导入',
  ),
);

final class _MusicName extends StatefulWidget {
  const _MusicName({
    required this.title,
    required this.initial,
    this.label = '歌单名称',
    this.maxLength = 80,
    this.submit = '保存',
  });
  final String title, initial, label, submit;
  final int maxLength;
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
      maxLength: widget.maxLength,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: Text(widget.submit),
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
        for (final list in services.musicLibrary.playlists.where(
          (list) => services.contentPolicy.textAllowed(list.name),
        ))
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, list.id),
            child: Text(list.name),
          ),
      ],
    ),
  );
  if (selected == null || !context.mounted) return;
  if (!services.music.allowed(track)) throw const FormatException('歌曲已被过滤');
  final id = selected;
  if (id == 'new') {
    final name = await musicName(context, '新建歌单');
    if (name == null) return;
    if (!services.music.allowed(track) ||
        !services.contentPolicy.textAllowed(name)) {
      throw const FormatException('歌单或歌曲已被过滤');
    }
    await services.musicLibrary.create(name, tracks: [track]);
  } else {
    final list = services.musicLibrary.playlists
        .where((list) => list.id == id)
        .firstOrNull;
    if (list == null || !services.contentPolicy.textAllowed(list.name)) {
      throw const FormatException('歌单已不可用');
    }
    await services.musicLibrary.add(id, track);
  }
  services.musicPlayer.prepareAddedTrack(track);
}

final class MusicTrackMenu extends StatelessWidget {
  const MusicTrackMenu({
    super.key,
    required this.services,
    required this.track,
    this.alternatives = const [],
  });
  final AppServices services;
  final MusicTrack track;
  final List<MusicTrack> alternatives;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '歌曲操作',
    onSelected: (value) => musicAction(
      context,
      () => switch (value) {
        'playlist' => addToMusicPlaylist(context, services, track),
        'next' => services.musicPlayer.enqueue(
          track,
          playNext: true,
          alternatives: alternatives,
        ),
        'queue' => services.musicPlayer.enqueue(
          track,
          alternatives: alternatives,
        ),
        _ => services.musicDownloads.download(track),
      },
    ),
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'playlist', child: Text('加入指定歌单')),
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
