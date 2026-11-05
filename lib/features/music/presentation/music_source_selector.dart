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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: services.musicBrowser,
    builder: (context, _) => _selector(context),
  );

  Widget _selector(BuildContext context) => Card(
    child: ListTile(
      title: DropdownButton<String>(
        value: value,
        isExpanded: true,
        items: [
          const DropdownMenuItem(
            value: 'all',
            child: Text('多源聚合 · 并发搜索', overflow: TextOverflow.ellipsis),
          ),
          for (final id in services.musicBrowser.orderedProviders)
            DropdownMenuItem(
              value: id,
              child: Row(
                children: [
                  if (services.musicBrowser.favoriteProviders.contains(id)) ...[
                    Icon(
                      Icons.star,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      musicSources[id]!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
      subtitle: Text(
        services.musicBrowser.preferenceNotice ?? '播放渠道 · 收藏渠道优先搜索',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != 'all')
            IconButton(
              tooltip: services.musicBrowser.favoriteProviders.contains(value)
                  ? '取消收藏音乐渠道'
                  : '收藏音乐渠道',
              onPressed: () => services.musicBrowser.setFavorite(
                value,
                !services.musicBrowser.favoriteProviders.contains(value),
              ),
              icon: Icon(
                services.musicBrowser.favoriteProviders.contains(value)
                    ? Icons.star
                    : Icons.star_outline,
              ),
              color: services.musicBrowser.favoriteProviders.contains(value)
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          IconButton(
            tooltip: '音乐渠道与 LX 音源',
            onPressed: () => showLxSources(context, services),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
    ),
  );
}
