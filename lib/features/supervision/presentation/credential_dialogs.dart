import 'package:flutter/material.dart';

Future<String?> newSupervisionPassword(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _NewPasswordDialog(),
    );

final class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog();
  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

final class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _password = TextEditingController(), _repeat = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _password.text;
    if (value.length < 8 || value.length > 128 || value.trim().isEmpty) {
      setState(() => _error = '密码需为 8–128 个字符');
    } else if (value != _repeat.text) {
      setState(() => _error = '两次输入不一致');
    } else {
      Navigator.pop(context, value);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('设置监管密码'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            maxLength: 128,
            decoration: const InputDecoration(labelText: '新密码（至少 8 字符）'),
          ),
          TextField(
            controller: _repeat,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            maxLength: 128,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: '再次输入密码'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('生成恢复码')),
    ],
  );
}

Future<bool> confirmRecoveryCode(BuildContext context, String code) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RecoveryCodeDialog(code),
    ) ??
    false;

final class _RecoveryCodeDialog extends StatefulWidget {
  const _RecoveryCodeDialog(this.code);
  final String code;
  @override
  State<_RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

final class _RecoveryCodeDialogState extends State<_RecoveryCodeDialog> {
  bool _saved = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('保存恢复码'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('恢复码只显示这一次。请自行保存在安全位置；普通数据备份不包含密码或恢复码。'),
          const SizedBox(height: 16),
          SelectableText(
            widget.code,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const Text('忘记密码时可凭此码重设。密码和恢复码均丢失时，应用内无法解除监管。'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _saved,
            title: const Text('我已妥善保存恢复码'),
            onChanged: (value) => setState(() => _saved = value ?? false),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('取消设置'),
      ),
      FilledButton(
        onPressed: _saved ? () => Navigator.pop(context, true) : null,
        child: const Text('完成设置'),
      ),
    ],
  );
}
