import 'package:flutter/material.dart';
import 'widgets.dart';

/// Only the caller's explicitly failed, completed probe results are eligible.
final class ProbeCleanupActions extends StatefulWidget {
  const ProbeCleanupActions({
    super.key,
    required this.ids,
    required this.noun,
    required this.onDisable,
    required this.onRemove,
  });
  final Set<String> ids;
  final String noun;
  final Future<void> Function(List<String>) onDisable, onRemove;
  @override
  State<ProbeCleanupActions> createState() => _ProbeCleanupActionsState();
}

final class _ProbeCleanupActionsState extends State<ProbeCleanupActions> {
  final _disabled = <String>{};
  final _removed = <String>{};
  bool _busy = false;

  Future<void> _apply(bool remove) => perform(context, () async {
    if (_busy) return;
    final ids = widget.ids
        .difference(_removed)
        .difference(remove ? <String>{} : _disabled)
        .toList();
    if (ids.isEmpty) return;
    final action = remove ? '删除' : '停用';
    final accepted = await confirm(
      context,
      '$action无效${widget.noun}',
      '将$action本次检测明确无效的 ${ids.length} 个${widget.noun}。超时、网络异常、取消及未检测项目不会被清理。${remove ? '删除后订阅更新不会自动恢复，可从已移除列表恢复。' : '可在已停用列表重新启用。'}',
    );
    if (!accepted || !mounted) return;
    setState(() => _busy = true);
    try {
      await (remove ? widget.onRemove(ids) : widget.onDisable(ids));
      if (!mounted) return;
      setState(() => (remove ? _removed : _disabled).addAll(ids));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      TextButton.icon(
        onPressed:
            _busy ||
                widget.ids.difference(_removed).difference(_disabled).isEmpty
            ? null
            : () => _apply(false),
        icon: const Icon(Icons.block),
        label: Text('停用无效${widget.noun}'),
      ),
      TextButton.icon(
        onPressed: _busy || widget.ids.difference(_removed).isEmpty
            ? null
            : () => _apply(true),
        icon: const Icon(Icons.delete_outline),
        label: Text('删除无效${widget.noun}'),
      ),
    ],
  );
}
