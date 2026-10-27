import 'package:flutter/material.dart';
import '../../sources/domain/video_source.dart';
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      return Row(
        key: const ValueKey('discovery-toolbar-row'),
        children: [
          SizedBox(width: wide ? 230 : 120, child: _channel()),
          const SizedBox(width: 12),
          Expanded(child: HomeSearch(onSearch: onSearch)),
          const SizedBox(width: 8),
          if (wide) ...[
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

  Widget _channel() => DropdownButtonFormField<String>(
    key: ValueKey('home-channel:$channel'),
    initialValue: sources.any((s) => s.id == channel) ? channel : '',
    isExpanded: true,
    decoration: const InputDecoration(labelText: '推荐频道', isDense: true),
    items: [
      DropdownMenuItem(
        value: '',
        child: Text(providerName, overflow: TextOverflow.ellipsis),
      ),
      for (final source in sources)
        DropdownMenuItem(
          value: source.id,
          child: Text(source.displayName, overflow: TextOverflow.ellipsis),
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
      }
    },
    itemBuilder: (_) => [
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
