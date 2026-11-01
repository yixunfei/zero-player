import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../data/public_music_sources.dart';
import 'music_actions.dart';
import 'music_player.dart';

final class MusicLibraryPanel extends StatefulWidget {
  const MusicLibraryPanel({
    super.key,
    required this.services,
    required this.view,
  });
  final AppServices services;
  final String view;
  @override
  State<MusicLibraryPanel> createState() => _MusicLibraryPanelState();
}

final class _MusicLibraryPanelState extends State<MusicLibraryPanel> {
  String? _playlist;
  AppServices get services => widget.services;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.musicLibrary,
      services.musicDownloads,
      services.contentPolicy,
    ]),
    builder: (context, _) => switch (widget.view) {
      'history' => _history(),
      'downloads' => _downloads(),
      _ => _playlists(),
    },
  );
  Widget _playlists() {
    final library = services.musicLibrary;
    final list = library.playlists.where((p) => p.id == _playlist).firstOrNull;
    if (list == null) return _playlistList();
    final tracks = list.tracks.where(services.music.allowed).toList();
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '返回歌单',
              onPressed: () => setState(() => _playlist = null),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(child: Text(list.name)),
            TextButton(
              onPressed: tracks.isEmpty
                  ? null
                  : () => services.musicPlayer.select(tracks, 0),
              child: const Text('播放全部'),
            ),
          ],
        ),
        for (var i = 0; i < tracks.length; i++)
          Card(
            child: ListTile(
              title: Text(tracks[i].title),
              subtitle: Text(tracks[i].artist),
              onTap: () => services.musicPlayer.select(tracks, i),
              trailing: PopupMenuButton<String>(
                onSelected: (action) => musicAction(
                  context,
                  () => action == 'remove'
                      ? library.remove(list.id, tracks[i].key)
                      : action == 'download'
                      ? services.musicDownloads.download(tracks[i])
                      : action == 'next' || action == 'queue'
                      ? services.musicPlayer.enqueue(
                          tracks[i],
                          playNext: action == 'next',
                        )
                      : library.move(
                          list.id,
                          tracks[i].key,
                          action == 'up' ? -1 : 1,
                        ),
                ),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'next', child: Text('下一首播放')),
                  const PopupMenuItem(value: 'queue', child: Text('加入播放队列')),
                  const PopupMenuItem(value: 'up', child: Text('上移')),
                  const PopupMenuItem(value: 'down', child: Text('下移')),
                  PopupMenuItem(
                    value: 'download',
                    enabled: tracks[i].canDownload,
                    child: const Text('下载离线'),
                  ),
                  const PopupMenuItem(value: 'remove', child: Text('移出歌单')),
                ],
              ),
            ),
          ),
        if (tracks.isEmpty) const Text('此歌单暂无可显示的歌曲。'),
      ],
    );
  }

  Widget _playlistList() {
    final library = services.musicLibrary;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => musicAction(context, () async {
              final name = await musicName(context, '新建歌单');
              if (name != null) await library.create(name);
            }),
            icon: const Icon(Icons.playlist_add),
            label: const Text('新建歌单'),
          ),
        ),
        if (library.playlists.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('建立自己的歌单，从歌曲操作菜单加入音乐。'),
          ),
        for (final item in library.playlists)
          Card(
            child: ListTile(
              title: Text(item.name),
              subtitle: Text(
                '${item.tracks.where(services.music.allowed).length} 首歌曲',
              ),
              onTap: () => setState(() => _playlist = item.id),
              trailing: PopupMenuButton<String>(
                onSelected: (action) => musicAction(context, () async {
                  if (action == 'delete') {
                    await library.delete(item.id);
                  } else {
                    final name = await musicName(
                      context,
                      '重命名歌单',
                      initial: item.name,
                    );
                    if (name != null) await library.rename(item.id, name);
                  }
                }),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除歌单（保留下载）')),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _history() => Column(
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () =>
              musicAction(context, services.musicLibrary.clearHistory),
          child: const Text('清空播放历史'),
        ),
      ),
      if (services.musicLibrary.history
          .where((h) => services.music.allowed(h.track))
          .isEmpty)
        const Text('暂无可显示的播放历史。播放音乐后可在这里继续收听。'),
      for (final item in services.musicLibrary.history.where(
        (h) => services.music.allowed(h.track),
      ))
        Card(
          child: ListTile(
            title: Text(item.track.title),
            subtitle: Text(
              '${item.track.artist} · ${musicTime(item.position)} · ${musicSources[item.track.provider]}',
            ),
            onTap: () => services.musicPlayer.select(
              [item.track],
              0,
              start: item.position,
            ),
            trailing: MusicTrackMenu(services: services, track: item.track),
          ),
        ),
    ],
  );
  Widget _downloads() => Column(
    children: [
      const Text('下载保存在本机应用目录，完成后优先离线播放。单首最多 128 MiB，总计 1 GiB；关闭应用会暂停任务。'),
      if (services.musicDownloads.items
          .where((i) => services.music.allowed(i.track))
          .isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('暂无可显示的离线音乐。从歌曲操作菜单选择“下载离线”。'),
        ),
      for (final item in services.musicDownloads.items.where(
        (i) => services.music.allowed(i.track),
      ))
        Card(
          child: ListTile(
            title: Text(item.track.title),
            subtitle: Text(
              '${switch (item.status) {
                'complete' => '已下载',
                'queued' => '排队中',
                'downloading' => '下载中',
                'paused' => '已暂停',
                _ => '下载失败',
              }} · ${(item.bytes / 1048576).toStringAsFixed(1)} MiB${item.error == null ? '' : '\n${item.error}'}',
            ),
            onTap: item.status == 'complete'
                ? () => services.musicPlayer.select([item.track], 0)
                : null,
            trailing: PopupMenuButton<String>(
              onSelected: (action) => musicAction(
                context,
                () => switch (action) {
                  'pause' => services.musicDownloads.pause(item.track),
                  'remove' => services.musicDownloads.remove(item.track),
                  'next' => services.musicPlayer.enqueue(
                    item.track,
                    playNext: true,
                  ),
                  'queue' => services.musicPlayer.enqueue(item.track),
                  _ => services.musicDownloads.download(item.track),
                },
              ),
              itemBuilder: (_) => [
                if (item.status == 'complete') ...[
                  const PopupMenuItem(value: 'next', child: Text('下一首播放')),
                  const PopupMenuItem(value: 'queue', child: Text('加入播放队列')),
                ],
                if ({'downloading', 'queued'}.contains(item.status))
                  const PopupMenuItem(value: 'pause', child: Text('暂停下载')),
                if ({'paused', 'failed'}.contains(item.status))
                  const PopupMenuItem(value: 'resume', child: Text('重试 / 续传')),
                const PopupMenuItem(value: 'remove', child: Text('删除本机下载')),
              ],
            ),
          ),
        ),
    ],
  );
}
