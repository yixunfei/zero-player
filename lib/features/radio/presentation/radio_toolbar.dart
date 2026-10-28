import 'package:flutter/material.dart';
import '../domain/radio_category.dart';

final class RadioToolbar extends StatelessWidget {
  const RadioToolbar({
    super.key,
    required this.query,
    required this.groups,
    required this.group,
    required this.favoritesOnly,
    required this.loading,
    required this.onGroup,
    required this.onFavorites,
    required this.onSearch,
    required this.onSubscriptions,
    required this.onInfo,
    required this.onRefresh,
    required this.onCollapse,
    required this.onCategory,
    this.category,
    this.updatedAt,
  });
  final TextEditingController query;
  final Iterable<String> groups;
  final String group;
  final bool favoritesOnly, loading;
  final DateTime? updatedAt;
  final ValueChanged<String> onGroup;
  final ValueChanged<bool> onFavorites;
  final RadioCategory? category;
  final ValueChanged<RadioCategory?> onCategory;
  final VoidCallback onCollapse;
  final VoidCallback onSearch, onSubscriptions, onInfo, onRefresh;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(),
        const SizedBox(height: 12),
        _filters(),
        const SizedBox(height: 8),
        _search(),
      ],
    ),
  );

  Widget _heading() => Row(
    children: [
      IconButton(
        tooltip: '收起广播页面',
        onPressed: onCollapse,
        icon: const Icon(Icons.keyboard_arrow_down),
      ),
      const Expanded(
        child: Text(
          '在线广播 · 实验阶段',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      IconButton(
        tooltip: '管理广播订阅',
        onPressed: onSubscriptions,
        icon: const Icon(Icons.playlist_add),
      ),
      IconButton(
        tooltip: '广播来源与说明',
        onPressed: onInfo,
        icon: const Icon(Icons.info_outline),
      ),
      IconButton(
        tooltip: '刷新广播列表',
        onPressed: loading ? null : onRefresh,
        icon: const Icon(Icons.refresh),
      ),
    ],
  );

  Widget _filters() => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ChoiceChip(
        label: const Text('全部（广播优先）'),
        selected: category == null,
        onSelected: (_) => onCategory(null),
      ),
      for (final type in RadioCategory.values)
        ChoiceChip(
          label: Text(type.label),
          selected: category == type,
          onSelected: (_) => onCategory(type),
        ),
      FilterChip(
        label: const Text('收藏电台'),
        selected: favoritesOnly,
        onSelected: onFavorites,
      ),
      if (updatedAt != null)
        Text('本地快照：${updatedAt!.toLocal().toString().substring(0, 16)}'),
    ],
  );

  Widget _search() => Row(
    children: [
      Expanded(
        child: TextField(
          controller: query,
          onChanged: (_) => onSearch(),
          decoration: InputDecoration(
            labelText: '搜索电台',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: '清空电台搜索',
              icon: const Icon(Icons.close),
              onPressed: () {
                query.clear();
                onSearch();
              },
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 110,
        child: DropdownButtonFormField<String>(
          key: ValueKey(group),
          initialValue: group,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '分组'),
          items: [
            const DropdownMenuItem(value: '', child: Text('全部')),
            for (final name in groups)
              DropdownMenuItem(
                value: name,
                child: Text(name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => onGroup(value ?? ''),
        ),
      ),
    ],
  );
}
