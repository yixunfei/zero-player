import 'package:flutter/material.dart';
import '../../sources/domain/video_source.dart';
import '../../sources/presentation/source_menu_label.dart';
import 'home_search.dart';

final class DiscoveryToolbar extends StatelessWidget {
  const DiscoveryToolbar({
    super.key,
    required this.sources,
    required this.channel,
    required this.providerName,
    required this.aggregate,
    required this.isDefault,
    required this.onChannel,
    required this.onLayout,
    required this.onSaveDefault,
    required this.onRefresh,
    required this.onSearch,
    this.isFavorite = false,
    this.onFavorite,
    this.onDetails,
  });
  final List<VideoSource> sources;
  final String channel;
  final String providerName;
  final bool aggregate;
  final bool isDefault;
  final ValueChanged<String> onChannel;
  final ValueChanged<bool> onLayout;
  final VoidCallback onSaveDefault;
  final VoidCallback onRefresh;
  final VoidCallback onSearch;
  final bool isFavorite;
  final VoidCallback? onFavorite, onDetails;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      if (constraints.maxWidth < 560) {
        return Column(
          key: const ValueKey('discovery-toolbar-column'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _channel(context)),
                const SizedBox(width: 8),
                _options(),
              ],
            ),
            const SizedBox(height: 8),
            HomeSearch(onSearch: onSearch),
          ],
        );
      }
      return Row(
        key: const ValueKey('discovery-toolbar-row'),
        children: [
          SizedBox(width: wide ? 230 : 120, child: _channel(context)),
          const SizedBox(width: 12),
          Expanded(child: HomeSearch(onSearch: onSearch)),
          const SizedBox(width: 8),
          if (wide) ...[
            if (onFavorite != null)
              IconButton(
                tooltip: isFavorite ? '取消收藏渠道' : '收藏渠道',
                onPressed: onFavorite,
                icon: Icon(isFavorite ? Icons.star : Icons.star_outline),
              ),
            if (onDetails != null)
              IconButton(
                tooltip: '渠道详情',
                onPressed: onDetails,
                icon: const Icon(Icons.info_outline),
              ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('单类浏览')),
                ButtonSegment(value: true, label: Text('分类聚合')),
              ],
              selected: {aggregate},
              onSelectionChanged: (value) => onLayout(value.single),
            ),
            IconButton(
              tooltip: isDefault ? '当前开屏默认' : '设为开屏默认',
              onPressed: isDefault ? null : onSaveDefault,
              icon: Icon(isDefault ? Icons.star : Icons.star_outline),
            ),
            IconButton(
              onPressed: onRefresh,
              tooltip: '刷新推荐',
              icon: const Icon(Icons.refresh),
            ),
          ] else
            _options(),
        ],
      );
    },
  );

  Widget _channel(BuildContext context) => DropdownButtonFormField<String>(
    // Recreate an open menu when its allowed choices change. Flutter's popup
    // otherwise retains the old entries even after the parent is rebuilt.
    key: ValueKey((channel, sources.map((s) => s.id).join(','))),
    initialValue: sources.any((s) => s.id == channel) ? channel : '',
    isExpanded: true,
    itemHeight: 48,
    menuMaxHeight: (MediaQuery.sizeOf(context).height - 160)
        .clamp(200.0, 420.0)
        .toDouble(),
    decoration: const InputDecoration(labelText: '推荐频道', isDense: true),
    items: [
      DropdownMenuItem(
        value: '',
        child: Text(providerName, overflow: TextOverflow.ellipsis),
      ),
      for (final source in sources)
        DropdownMenuItem(
          value: source.id,
          child: Row(
            children: [
              if (source.favorite)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.star, size: 16),
                ),
              Expanded(child: SourceMenuLabel(source)),
            ],
          ),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChannel(value);
    },
  );

  Widget _options() => PopupMenuButton<String>(
    tooltip: '首页选项',
    onSelected: (action) {
      switch (action) {
        case 'single':
          onLayout(false);
        case 'aggregate':
          onLayout(true);
        case 'default':
          onSaveDefault();
        case 'refresh':
          onRefresh();
        case 'favorite':
          onFavorite?.call();
        case 'details':
          onDetails?.call();
      }
    },
    itemBuilder: (_) => [
      if (onFavorite != null)
        PopupMenuItem(
          value: 'favorite',
          child: Text(isFavorite ? '★ 取消收藏渠道' : '☆ 收藏渠道'),
        ),
      if (onDetails != null)
        const PopupMenuItem(value: 'details', child: Text('渠道详情')),
      CheckedPopupMenuItem(
        value: 'single',
        checked: !aggregate,
        child: const Text('单类浏览'),
      ),
      CheckedPopupMenuItem(
        value: 'aggregate',
        checked: aggregate,
        child: const Text('分类聚合'),
      ),
      PopupMenuItem(
        value: 'default',
        enabled: !isDefault,
        child: Text(isDefault ? '当前开屏默认' : '设为开屏默认'),
      ),
      const PopupMenuItem(value: 'refresh', child: Text('刷新推荐')),
    ],
  );
}
