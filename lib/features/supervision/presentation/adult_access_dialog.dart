import 'package:flutter/material.dart';
import '../application/installation_access.dart';

Future<bool> verifyAdultFilterAccess(
  BuildContext context,
  InstallationAccess access, {
  bool restoringBackup = false,
}) async {
  await access.load();
  if (!context.mounted) return false;
  if (access.adultVerified) return true;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AdultAccessDialog(access, restoringBackup),
      ) ??
      false;
}

final class _AdultAccessDialog extends StatefulWidget {
  const _AdultAccessDialog(this.access, this.restoringBackup);
  final InstallationAccess access;
  final bool restoringBackup;
  @override
  State<_AdultAccessDialog> createState() => _AdultAccessDialogState();
}

final class _AdultAccessDialogState extends State<_AdultAccessDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.access.verifyAdultPassword(_password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FormatException ? error.message : '验证状态保存失败，请重试';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.restoringBackup ? '验证备份中的成人过滤设置' : '首次关闭成人过滤'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.restoringBackup)
              const Text('此备份保存了关闭成人过滤的偏好。恢复前需验证本机访问密码，监管开启时仍强制过滤。'),
            const Text(
              '关闭后可能显示成人频道和节目，请确认适合当前使用者。'
              '首次关闭需要验证访问密码，与监管密码不同；验证成功后本机不再重复要求此验证。'
              '监管模式开启期间仍禁止关闭成人过滤。',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              autofocus: true,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              enabled: !_busy,
              maxLength: 128,
              decoration: const InputDecoration(labelText: '访问密码'),
              onSubmitted: (_) => _verify(),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: Text(widget.restoringBackup ? '验证并继续恢复' : '验证并关闭过滤'),
        ),
      ],
    ),
  );
}
