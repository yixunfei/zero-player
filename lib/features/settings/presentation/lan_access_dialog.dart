import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../supervision/presentation/sensitive_action.dart';
import '../data/lan_access_store.dart';

Future<void> showLanAccess(BuildContext context, AppServices services) =>
    perform(context, () async {
      await services.lanAccess.load();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _LanAccessDialog(services: services),
      );
    });

final class _LanAccessDialog extends StatefulWidget {
  const _LanAccessDialog({required this.services});
  final AppServices services;
  @override
  State<_LanAccessDialog> createState() => _LanAccessDialogState();
}

final class _LanAccessDialogState extends State<_LanAccessDialog> {
  bool _busy = false;
  LanAccessStore get access => widget.services.lanAccess;

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await perform(
        context,
        () => runSensitive(
          context,
          widget.services.supervision,
          SensitiveOperation.settings,
          action,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() => perform(context, () async {
    final values = await inputDialog(context, '授权局域网媒体服务', [
      '地址，例如 http://192.168.1.10:8080',
    ], action: '检查地址');
    if (values == null || !mounted) return;
    final origin = LanAccessStore.validate(values.single);
    if (!await confirm(
      context,
      '授权 $origin',
      '应用将允许访问此 IP、端口和协议下的所有路径，授权不按渠道隔离。请仅授权你信任的媒体服务，避免路由器管理界面。\n\n'
          'HTTP 跨站重定向或跨站 HLS 子资源不能借用此授权；其他局域网服务需单独授权。撤销时会中断现有网络连接。',
    )) {
      return;
    }
    if (mounted) await _change(() => access.grant(origin));
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('局域网访问授权'),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '默认拦截内网访问。按协议、局域网 IP 和端口逐项授权，'
            '不接受通配符、域名、本机回环或链路本地地址。授权仅保存在此设备，不随源配置或备份导入。',
          ),
          const SizedBox(height: 12),
          if (access.origins.isEmpty) const Text('尚未授权任何局域网服务'),
          if (access.origins.isNotEmpty)
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final origin in access.origins)
                      ListTile(
                        title: Text(origin),
                        trailing: TextButton(
                          onPressed: _busy
                              ? null
                              : () => _change(() => access.revoke(origin)),
                          child: const Text('撤销'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      FilledButton(onPressed: _busy ? null : _add, child: const Text('添加授权')),
    ],
  );
}
