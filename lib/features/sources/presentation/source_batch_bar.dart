import '../../supervision/presentation/sensitive_action.dart';
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
        OutlinedButton.icon(
          onPressed:
              items.any((s) => s.enabled && !s.suppressed && s.possiblyInvalid)
              ? () => _disablePossiblyInvalid(context)
              : null,
          icon: const Icon(Icons.block),
          label: const Text('停用可能失效'),
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
    if (!context.mounted) return;
    if (!await runSensitive(
      context,
      services.supervision,
      SensitiveOperation.channels,
      () =>
          services.sources.batch(ids, enabled: enabled, suppressed: suppressed),
      needed: enabled == true || suppressed == false,
    )) {
      return;
    }
    onSelection({});
  });

  Future<void> _disablePossiblyInvalid(BuildContext context) =>
      perform(context, () async {
        final targets = (await services.sources.all())
            .where((s) => s.enabled && s.possiblyInvalid)
            .map((s) => s.id)
            .toList();
        if (!context.mounted || targets.isEmpty) return;
        if (!await confirm(
          context,
          '停用 ${targets.length} 个可能失效渠道',
          '包括超时、网络异常或接口失败等已标记来源。仅停用，不移除；之后可以手动启用。',
        )) {
          return;
        }
        final count = await services.sources.disablePossiblyInvalid(targets);
        onSelection({});
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已停用 $count 个可能失效渠道')));
        }
      });
}
