import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/music_catalog_api.dart';

final class MusicCatalogPicker extends StatelessWidget {
  const MusicCatalogPicker({
    super.key,
    required this.options,
    required this.group,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<MusicCatalogOption> options;
  final String? group, selected;
  final String label;
  final ValueChanged<MusicCatalogOption> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final groups = options.map((item) => item.group).toSet();
    final visible = options.where((item) => item.group == group).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (groups.length > 1)
          Wrap(
            spacing: 8,
            children: [
              for (final value in groups)
                ChoiceChip(
                  label: Text(value),
                  selected: value == group,
                  onSelected: (active) {
                    if (active) {
                      onSelected(
                        options.firstWhere((item) => item.group == value),
                      );
                    }
                  },
                ),
            ],
          ),
        if (visible.isNotEmpty)
          DropdownButton<MusicCatalogOption>(
            isExpanded: true,
            value: visible.where((option) => option.id == selected).firstOrNull,
            hint: Text(label),
            menuMaxHeight: 440,
            items: [
              for (final option in visible)
                DropdownMenuItem(
                  value: option,
                  child: Text(option.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) onSelected(value);
            },
          ),
      ],
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
