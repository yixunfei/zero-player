import 'package:flutter/material.dart';
import '../../../app/widgets.dart';

/// An explicit choice; a failed probe never silently disables a source.
final class BlockSourceButton extends StatelessWidget {
  const BlockSourceButton({
    super.key,
    required this.name,
    required this.onBlock,
  });
  final String name;
  final Future<void> Function() onBlock;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.block, size: 18),
    label: const Text('屏蔽渠道？'),
    onPressed: () async {
      final accepted = await confirm(
        context,
        '屏蔽 $name？',
        '该渠道将持续停用，不再参与搜索、推荐及自动换源。当前已开始的播放不受影响，可在源管理中重新启用。',
      );
      if (accepted && context.mounted) {
        await perform(context, onBlock, success: '已屏蔽，可在源管理中恢复');
      }
    },
  );
}
