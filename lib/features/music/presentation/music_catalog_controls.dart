import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/music_catalog_api.dart';

/// Source-side tag groups rendered as a full grid, mirroring the platform's
/// category page instead of hiding entries inside a dropdown.
final class MusicTagGrid extends StatelessWidget {
  const MusicTagGrid({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.loginRequiredHint = '此分类需在源站登录后浏览',
  });
  final List<MusicCatalogOption> options;
  final String? selected;
  final ValueChanged<MusicCatalogOption> onSelected;
  final String loginRequiredHint;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final groups = <String, List<MusicCatalogOption>>{};
    for (final option in options) {
      groups.putIfAbsent(option.group, () => []).add(option);
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in groups.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    entry.key,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in entry.value)
                      if (option.id.startsWith('account:'))
                        Tooltip(
                          message: loginRequiredHint,
                          child: ChoiceChip(
                            label: Text(option.name),
                            selected: false,
                            onSelected: null,
                          ),
                        )
                      else
                        ChoiceChip(
                          label: Text(option.name),
                          selected: option.id == selected,
                          onSelected: (active) {
                            if (active) onSelected(option);
                          },
                        ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Grouped chart navigation: a sidebar on wide layouts, group chips plus a
/// horizontally scrollable chart row on narrow layouts.
final class MusicChartNav extends StatefulWidget {
  const MusicChartNav({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.compact,
  });
  final List<MusicCatalogOption> options;
  final String? selected;
  final ValueChanged<MusicCatalogOption> onSelected;
  final bool compact;

  @override
  State<MusicChartNav> createState() => _MusicChartNavState();
}

final class _MusicChartNavState extends State<MusicChartNav> {
  String? _group;

  @override
  void initState() {
    super.initState();
    _group = _selectedGroup ?? widget.options.firstOrNull?.group;
  }

  String? get _selectedGroup => widget.options
      .where((option) => option.id == widget.selected)
      .firstOrNull
      ?.group;

  @override
  void didUpdateWidget(MusicChartNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    final groups = widget.options.map((option) => option.group).toSet();
    if (widget.selected != oldWidget.selected && _selectedGroup != null) {
      _group = _selectedGroup;
    } else if (!groups.contains(_group)) {
      _group = widget.options.firstOrNull?.group;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    final groups = <String, List<MusicCatalogOption>>{};
    for (final option in widget.options) {
      groups.putIfAbsent(option.group, () => []).add(option);
    }
    return widget.compact
        ? _compact(context, groups)
        : _sidebar(context, groups);
  }

  Widget _compact(
    BuildContext context,
    Map<String, List<MusicCatalogOption>> groups,
  ) {
    final visible = groups[_group] ?? groups.values.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final group in groups.keys)
              ChoiceChip(
                label: Text(group),
                selected: group == _group,
                onSelected: (active) {
                  if (active) setState(() => _group = group);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              for (final option in visible)
                ChoiceChip(
                  label: Text(option.name),
                  selected: option.id == widget.selected,
                  onSelected: (active) {
                    if (active) widget.onSelected(option);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sidebar(
    BuildContext context,
    Map<String, List<MusicCatalogOption>> groups,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final option in entry.value)
            _tile(context, option, scheme),
        ],
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    MusicCatalogOption option,
    ColorScheme scheme,
  ) {
    final selected = option.id == widget.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.onSelected(option),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              option.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurface,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class MusicCatalogCopyButton extends StatelessWidget {
  const MusicCatalogCopyButton({
    super.key,
    required this.uri,
    required this.label,
  });
  final Uri uri;
  final String label;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    icon: const Icon(Icons.link),
    onPressed: () async {
      var message = '网页链接已复制';
      try {
        await Clipboard.setData(ClipboardData(text: '$uri'));
      } on PlatformException {
        message = '无法访问系统剪贴板';
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    },
  );
}