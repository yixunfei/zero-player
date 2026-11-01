import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../data/public_music_sources.dart';
import 'lx_sources_dialog.dart';

final class MusicSourceSelector extends StatelessWidget {
  const MusicSourceSelector({
    super.key,
    required this.services,
    required this.value,
    required this.onChanged,
  });
  final AppServices services;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.library_music_outlined),
      title: DropdownButton<String>(
        value: value,
        isExpanded: true,
        items: [
          const DropdownMenuItem(value: 'all', child: Text('多源聚合 · 并发搜索')),
          for (final item in musicSources.entries)
            DropdownMenuItem(
              value: item.key,
              child: Text(item.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
      subtitle: Text(
        services.musicBrowser.preferenceNotice ?? '播放渠道 · 推荐封面独立于音乐来源',
      ),
      trailing: IconButton(
        tooltip: '音乐渠道与 LX 音源',
        onPressed: () => showLxSources(context, services),
        icon: const Icon(Icons.tune),
      ),
    ),
  );
}
