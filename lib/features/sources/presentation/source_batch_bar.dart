import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../domain/video_source.dart';

final class SourceBatchBar extends StatelessWidget {
  const SourceBatchBar({
    super.key,
    required this.services,
    required this.items,
    required this.selected,
    required this.onSelection,
    required this.showRemoved,
    required this.onShowRemoved,
  });
  final AppServices services;
  final List<VideoSource> items;
  final Set<String> selected;
  final ValueChanged<Set<String>> onSelection;
  final bool showRemoved;
  final ValueChanged<bool> onShowRemoved;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${items.where((s) => s.enabled && !s.suppressed).length} 已启用 / ${items.length} 个源',
        ),
        FilterChip(
          label: Text('多选 ${selected.length}'),
          selected: selected.isNotEmpty,
          onSelected: (_) => onSelection(
            selected.length == items.length
                ? {}
                : items.map((s) => s.id).toSet(),
          ),
        ),
        TextButton(
          onPressed: () => _apply(context, enabled: true),
          child: Text(selected.isEmpty ? '全部启用' : '启用所选'),
        ),
        TextButton(
          onPressed: () => _apply(context, enabled: false),
          child: Text(selected.isEmpty ? '全部停用' : '停用所选'),
        ),
        TextButton(
          onPressed: () => _apply(context, suppressed: true),
          child: Text(selected.isEmpty ? '全部移除' : '移除所选'),
        ),
        if (showRemoved)
          TextButton(
            onPressed: () => _apply(context, suppressed: false),
            child: Text(selected.isEmpty ? '恢复全部' : '恢复所选'),
          ),
        FilterChip(
          label: const Text('显示已移除'),
          selected: showRemoved,
          onSelected: onShowRemoved,
        ),
      ],
    ),
  );

  Future<void> _apply(
    BuildContext context, {
    bool? enabled,
    bool? suppressed,
  }) => perform(context, () async {
    final ids = (selected.isEmpty ? items.map((s) => s.id) : selected).toList();
    if (suppressed == true &&
        !await confirm(
          context,
          '移除 ${ids.length} 个源',
          '移除后不再参与搜索和换源。可在“显示已移除”中恢复，已有下载文件保留。',
        )) {
      return;
    }
    await services.sources.batch(ids, enabled: enabled, suppressed: suppressed);
    onSelection({});
  });
}
