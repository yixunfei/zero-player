import 'package:flutter/material.dart';
import '../application/supervision_controller.dart';
import '../domain/supervision_rules.dart';

export '../domain/supervision_rules.dart' show SensitiveOperation;

/// The grant stays inside this awaited operation. Cancel never calls the body.
Future<bool> runSensitive(
  BuildContext context,
  SupervisionController? guard,
  SensitiveOperation operation,
  Future<void> Function() action, {
  bool needed = true,
  bool recovery = false,
  String? explanation,
}) async {
  if (guard == null || !needed) {
    await action();
    return true;
  }
  await guard.load();
  if (!context.mounted) return false;
  String? secret;
  if (guard.needsPassword(operation)) {
    secret = await showDialog<String>(
      context: context,
      builder: (_) =>
          _SecretDialog(recovery: recovery, explanation: explanation),
    );
    if (secret == null || !context.mounted) return false;
  }
  await guard.execute(
    operation,
    action,
    password: recovery ? secret?.trim() : secret,
    useRecovery: recovery,
  );
  return true;
}

final class _SecretDialog extends StatefulWidget {
  const _SecretDialog({required this.recovery, this.explanation});
  final bool recovery;
  final String? explanation;
  @override
  State<_SecretDialog> createState() => _SecretDialogState();
}

final class _SecretDialogState extends State<_SecretDialog> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (_text.text.isNotEmpty) Navigator.pop(context, _text.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.recovery ? '使用恢复码' : '验证监管密码'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.recovery
                ? '恢复码仅用于重设密码，完成后旧恢复码失效。'
                : (widget.explanation ?? '仅授权本次操作；下一次敏感操作仍需验证。'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            maxLength: 256,
            decoration: InputDecoration(
              labelText: widget.recovery ? '恢复码' : '监管密码',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('验证并继续')),
    ],
  );
}
