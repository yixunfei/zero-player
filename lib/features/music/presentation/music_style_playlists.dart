import 'dart:async';

import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../supervision/domain/supervision_rules.dart';
import '../data/music_style_catalog.dart';
import '../domain/music_track.dart';
import 'music_actions.dart';

final class MusicStylePlaylists extends StatefulWidget {
  const MusicStylePlaylists({super.key, required this.services});
  final AppServices services;

  @override
  State<MusicStylePlaylists> createState() => _MusicStylePlaylistsState();
}

final class _MusicStylePlaylistsState extends State<MusicStylePlaylists> {
  late final _catalog = MusicStyleCatalog(widget.services.music);
  final _query = TextEditingController(text: '爵士');
  String _provider = 'neteasePlaylist';
  CancellationToken? _request;
  List<MusicStylePlaylist> _lists = [];
  MusicStylePlaylist? _selected;
  List<MusicTrack> _tracks = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_search(_query.text));
  }

  @override
  void dispose() {
    _request?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String value) => _load(
    () {
      _query.text = value;
      _selected = null;
      _lists = [];
    },
    (token) async {
      final lists = await _catalog.search(_provider, value, token);
      if (mounted && !token.isCancelled) setState(() => _lists = lists);
    },
  );

  Future<void> _open(MusicStylePlaylist list) => _load(
    () {
      _selected = list;
      _tracks = [];
    },
    (token) async {
      final tracks = await _catalog.tracks(list, token);
      if (mounted && !token.isCancelled) setState(() => _tracks = tracks);
    },
  );

  Future<void> _load(
    VoidCallback reset,
    Future<void> Function(CancellationToken) action,
  ) async {
    _request?.cancel();
    final token = CancellationToken();
    setState(() {
      _request = token;
      _error = null;
      reset();
    });
    try {
      await action(token);
    } catch (failure) {
      if (mounted && !token.isCancelled) {
        setState(
          () => _error = switch (failure) {
            ContentBlocked() => '歌单或平台已被当前过滤规则屏蔽',
            FormatException() => failure.message,
            _ => '无法加载歌单，请稍后重试',
          },
        );
      }
    } finally {
      if (mounted && !token.isCancelled) setState(() => _request = null);
    }
  }

  void _back() {
    _request?.cancel();
    setState(() {
      _request = null;
      _selected = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.services.contentPolicy,
    builder: (context, _) {
      final selected = _selected;
      if (selected != null) return _detail(selected);
      final lists = _lists.where(_catalog.allowed).toList();
      return ListView.builder(
        key: const PageStorageKey('music-style-lists'),
        padding: const EdgeInsets.all(16),
        itemCount: lists.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return _controls(lists.isEmpty);
          final list = lists[i - 1];
          return ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: Text(
              list.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(list),
          );
        },
      );
    },
  );

  Widget _controls(bool empty) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        children: [
          for (final entry in musicPlaylistProviders.entries)
            ChoiceChip(
              selected: _provider == entry.key,
              label: Text(entry.value),
              onSelected: (_) {
                _provider = entry.key;
                unawaited(
                  _search(
                    entry.key != 'neteasePlaylist' &&
                            !musicStyles.containsKey(_query.text)
                        ? musicStyles.keys.first
                        : _query.text,
                  ),
                );
              },
            ),
        ],
      ),
      if (_provider == 'neteasePlaylist')
        TextField(
          controller: _query,
          maxLength: 100,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            labelText: '搜索歌单风格或名称',
            counterText: '',
            suffixIcon: IconButton(
              tooltip: '搜索歌单',
              onPressed: () => _search(_query.text),
              icon: const Icon(Icons.search),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(
          spacing: 8,
          children: [
            for (final style in musicStyles.keys)
              ChoiceChip(
                selected: _query.text == style,
                label: Text(style),
                onSelected: (_) => _search(style),
              ),
          ],
        ),
      ),
      _status(empty ? '没有找到可显示的歌单' : null, () => _search(_query.text)),
    ],
  );

  Widget _detail(MusicStylePlaylist list) {
    final allowed = _catalog.allowed(list);
    final services = widget.services;
    final tracks = allowed
        ? _tracks.where(services.music.allowed).toList()
        : <MusicTrack>[];
    return ListView.builder(
      key: ValueKey('${list.provider}:${list.id}'),
      padding: const EdgeInsets.all(16),
      itemCount: tracks.length + 1,
      itemBuilder: (context, index) {
        if (index > 0) {
          final track = tracks[index - 1];
          return ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: MusicTrackMenu(services: services, track: track),
            onTap: () => services.musicPlayer.select(tracks, index - 1),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '返回风格歌单',
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(child: Text(allowed ? list.name : '歌单已被过滤')),
                TextButton(
                  onPressed: tracks.isEmpty
                      ? null
                      : () => services.musicPlayer.select(tracks, 0),
                  child: const Text('匹配播放'),
                ),
              ],
            ),
            if (allowed)
              _status(
                tracks.isEmpty
                    ? '歌单内没有可显示的曲目'
                    : '共获取 ${tracks.length} 首 · 播放时匹配可用渠道',
                () => _open(list),
              ),
          ],
        );
      },
    );
  }

  Widget _status(String? idle, VoidCallback retry) {
    if (_request != null) return const LinearProgressIndicator();
    if (_error case final error?) {
      return ListTile(
        title: Text(error),
        trailing: TextButton(onPressed: retry, child: const Text('重试')),
      );
    }
    return idle == null ? const SizedBox.shrink() : Text(idle);
  }
}
