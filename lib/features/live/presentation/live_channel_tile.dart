import 'package:flutter/material.dart';
import '../../../app/poster_image.dart';
import '../domain/live_channel.dart';

enum LiveChannelAction { info, favorite, probe, epg, toggle }

/// Each visible channel owns its focus so D-pad selection and scroll-to-focus
/// use the channel itself, independently of its secondary action menu.
final class LiveChannelTile extends StatefulWidget {
  const LiveChannelTile({
    super.key,
    required this.channel,
    required this.selected,
    required this.onSelect,
    required this.onPlay,
    required this.onAction,
  });
  final LiveChannel channel;
  final bool selected;
  final VoidCallback onSelect, onPlay;
  final ValueChanged<LiveChannelAction> onAction;
  @override
  State<LiveChannelTile> createState() => _LiveChannelTileState();
}

final class _LiveChannelTileState extends State<LiveChannelTile> {
  late final _focus = FocusNode(debugLabel: 'channel:${widget.channel.id}');
  bool _focused = false;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: widget.selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: _focused ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          key: ValueKey('live-focus-${channel.id}'),
          focusNode: _focus,
          autofocus: widget.selected,
          borderRadius: BorderRadius.circular(14),
          onFocusChange: (focused) {
            setState(() => _focused = focused);
            if (focused) widget.onSelect();
          },
          onTap: () {
            widget.onSelect();
            if (channel.health.enabled && channel.urls.isNotEmpty) {
              widget.onPlay();
            }
          },
          child: ListTile(
            leading: SizedBox(
              width: 44,
              height: 44,
              child: channel.logo.isEmpty
                  ? Icon(channel.health.enabled ? Icons.live_tv : Icons.tv_off)
                  : PosterImage(url: channel.logo, fit: BoxFit.contain),
            ),
            title: Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${channel.health.label} · ${channel.listName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _menu(channel),
          ),
        ),
      ),
    );
  }

  Widget _menu(LiveChannel channel) => PopupMenuButton<LiveChannelAction>(
    tooltip: '频道操作',
    onSelected: widget.onAction,
    itemBuilder: (_) => [
      const PopupMenuItem(value: LiveChannelAction.info, child: Text('查看频道信息')),
      PopupMenuItem(
        value: LiveChannelAction.favorite,
        child: Text(channel.favorite ? '取消收藏' : '收藏'),
      ),
      const PopupMenuItem(value: LiveChannelAction.probe, child: Text('检测可用性')),
      const PopupMenuItem(value: LiveChannelAction.epg, child: Text('节目单')),
      PopupMenuItem(
        value: LiveChannelAction.toggle,
        child: Text(channel.health.enabled ? '停用频道' : '重新启用'),
      ),
    ],
  );
}
