import 'package:flutter/material.dart';
import '../domain/live_channel.dart';

final class LiveChannelFilter {
  const LiveChannelFilter({
    this.category = '',
    this.language = '',
    this.resolution = '',
  });
  final String category, language, resolution;
  bool matches(LiveChannel c) =>
      _matches(category, c.categories) &&
      _matches(language, c.languages) &&
      _matches(resolution, c.resolutions);
  bool _matches(String selected, List<String> values) =>
      selected.isEmpty ||
      (selected == '未知' ? values.isEmpty : values.contains(selected));
  bool get active =>
      category.isNotEmpty || language.isNotEmpty || resolution.isNotEmpty;
}

class LiveChannelFilters extends StatelessWidget {
  const LiveChannelFilters({
    super.key,
    required this.channels,
    required this.value,
    required this.onChanged,
  });
  final List<LiveChannel> channels;
  final LiveChannelFilter value;
  final ValueChanged<LiveChannelFilter> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Wrap(
      spacing: 8,
      children: [
        _menu(
          '分类',
          value.category,
          channels.expand((c) => c.categories),
          (v) => onChanged(
            LiveChannelFilter(
              category: v,
              language: value.language,
              resolution: value.resolution,
            ),
          ),
        ),
        _menu(
          '语言',
          value.language,
          channels.expand((c) => c.languages),
          (v) => onChanged(
            LiveChannelFilter(
              category: value.category,
              language: v,
              resolution: value.resolution,
            ),
          ),
        ),
        _menu(
          '分辨率',
          value.resolution,
          channels.expand((c) => c.resolutions),
          (v) => onChanged(
            LiveChannelFilter(
              category: value.category,
              language: value.language,
              resolution: v,
            ),
          ),
        ),
        if (value.active)
          TextButton(
            onPressed: () => onChanged(const LiveChannelFilter()),
            child: const Text('重置筛选'),
          ),
      ],
    ),
  );
  Widget _menu(
    String title,
    String selected,
    Iterable<String> values,
    ValueChanged<String> onSelected,
  ) {
    final options = values.toSet()..remove('未知');
    if (selected.isNotEmpty && selected != '未知') options.add(selected);
    return PopupMenuButton<String>(
      tooltip: '按$title筛选',
      onSelected: onSelected,
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text('全部$title')),
        const PopupMenuItem(value: '未知', child: Text('未知')),
        for (final v in options.toList()..sort())
          PopupMenuItem(value: v, child: Text(v)),
      ],
      child: Chip(
        label: Text('$title：${selected.isEmpty ? '全部' : selected}'),
        avatar: const Icon(Icons.filter_list, size: 16),
      ),
    );
  }
}
