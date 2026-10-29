import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../supervision/presentation/sensitive_action.dart';

final class ContentFilterProtection extends StatefulWidget {
  const ContentFilterProtection({super.key, required this.services});
  final AppServices services;
  @override
  State<ContentFilterProtection> createState() =>
      _ContentFilterProtectionState();
}

final class _ContentFilterProtectionState
    extends State<ContentFilterProtection> {
  bool _busy = false;
  Future<void> _change(bool value) => perform(context, () async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await runSensitive(
        context,
        widget.services.supervision,
        SensitiveOperation.supervision,
        () => widget.services.installationAccess.setContentFilterProtection(
          value,
        ),
        explanation: '修改内容过滤的密码保护规则，需要验证监管密码。',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.services.supervision,
      widget.services.installationAccess,
    ]),
    builder: (context, _) {
      final guard = widget.services.supervision;
      return Column(
        children: [
          SwitchListTile(
            title: const Text('内容过滤设置需要监管验证'),
            subtitle: Text(
              guard.configured
                  ? '默认关闭。开启后，监管期间关闭特征跳过或增强识别、修改策略/时长、管理特征均需验证。修改本开关始终需要监管密码。'
                  : '默认关闭。请先设置监管密码，才能修改此开关。成人过滤规则不受此开关影响。',
            ),
            value: widget.services.installationAccess.protectContentFilter,
            onChanged: _busy || !guard.configured || guard.corrupted
                ? null
                : _change,
          ),
          if (!guard.configured)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.push('/supervision'),
                child: const Text('设置监管密码'),
              ),
            ),
        ],
      );
    },
  );
}
