import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../domain/supervision_rules.dart';
import 'blocked_channel_picker.dart';
import 'credential_dialogs.dart';
import 'sensitive_action.dart';

final class SupervisionPage extends StatefulWidget {
  const SupervisionPage({super.key, required this.services});
  final AppServices services;
  @override
  State<SupervisionPage> createState() => _SupervisionPageState();
}

final class _SupervisionPageState extends State<SupervisionPage> {
  bool _busy = false;

  Future<void> _operate(
    Future<void> Function() action, {
    bool recovery = false,
  }) => perform(context, () async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await runSensitive(
        context,
        widget.services.supervision,
        SensitiveOperation.supervision,
        action,
        recovery: recovery,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  Future<void> _credentials({bool recovery = false}) async {
    final password = await newSupervisionPassword(context);
    if (password == null || !mounted) return;
    await _operate(() async {
      final draft = await widget.services.supervision.prepareCredentials(
        password,
      );
      if (!mounted || !await confirmRecoveryCode(context, draft.recoveryCode)) {
        return;
      }
      if (!widget.services.supervision.configured) {
        await widget.services.settings.update({'filterAdult': true});
      }
      await widget.services.supervision.saveCredentials(draft);
      if (mounted) message(context, '监管凭据已保存；每次敏感操作均需重新验证');
    }, recovery: recovery);
  }

  Future<void> _addKeyword() async {
    final values = await inputDialog(context, '屏蔽关键词', ['关键词（最多 80 字符）']);
    if (values == null || !mounted) return;
    await _operate(
      () => widget.services.supervision.updateRules(
        SupervisionRules(
          channels: widget.services.supervision.rules.channels,
          keywords: {
            ...widget.services.supervision.rules.keywords,
            values.single.trim(),
          },
        ),
      ),
    );
  }

  Future<void> _addChannel() async {
    final channel = await pickBlockedChannel(context, widget.services);
    if (channel == null || !mounted) return;
    await _operate(
      () => widget.services.supervision.updateRules(
        SupervisionRules(
          channels: {
            for (final c in widget.services.supervision.rules.channels)
              c.key: c,
            channel.key: channel,
          }.values,
          keywords: widget.services.supervision.rules.keywords,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('监管模式')),
    body: ListenableBuilder(
      listenable: widget.services.supervision,
      builder: (context, _) {
        final guard = widget.services.supervision;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_busy) const LinearProgressIndicator(),
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('每次操作单独验证'),
              subtitle: Text('覆盖点播、直播和广播。关闭成人过滤、启用或导入渠道、恢复备份及修改监管规则都需要密码。'),
            ),
            if (guard.corrupted)
              const ListTile(
                title: Text('监管配置损坏，已保持锁定'),
                subtitle: Text('不会通过普通备份或恢复默认来源绕过锁定。'),
              ),
            if (!guard.configured)
              ListTile(
                title: const Text('首次设置密码和恢复码'),
                subtitle: const Text('完成后立即启用监管模式'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : _credentials,
              )
            else ...[
              SwitchListTile(
                title: const Text('启用监管模式'),
                value: guard.enabled,
                subtitle: const Text('关闭监管不会删除密码和规则；再次启用仍需验证'),
                onChanged: _busy || guard.corrupted
                    ? null
                    : (value) => _operate(() => guard.setEnabled(value)),
              ),
              ListTile(
                title: const Text('修改密码 / 重新生成恢复码'),
                onTap: _busy || guard.corrupted ? null : _credentials,
              ),
              ListTile(
                title: const Text('忘记密码：使用恢复码重设'),
                subtitle: const Text('保留屏蔽规则，生成新的恢复码，旧恢复码失效'),
                onTap: _busy || guard.corrupted
                    ? null
                    : () => _credentials(recovery: true),
              ),
              ..._ruleControls(),
            ],
            const SizedBox(height: 24),
            const Text(
              '成人过滤依据来源标记、分类和文字，不分析视频画面。漏标内容可用频道或关键词补充屏蔽。监管仅保护本应用内的操作，不能防止拥有本机数据修改权限的人篡改或清空数据。',
            ),
          ],
        );
      },
    ),
  );
  List<Widget> _ruleControls() {
    final guard = widget.services.supervision;
    return [
      const Divider(),
      ListTile(
        title: const Text('屏蔽频道'),
        subtitle: Text('已设置 ${guard.rules.channels.length} 个'),
        trailing: IconButton(
          tooltip: '添加屏蔽频道',
          icon: const Icon(Icons.add),
          onPressed: _busy || guard.corrupted ? null : _addChannel,
        ),
      ),
      for (final channel in guard.rules.channels)
        ListTile(
          title: Text(channel.label),
          subtitle: Text(switch (channel.key.split(':').first) {
            'vod' => '点播来源',
            'radio' => '广播电台',
            _ => '直播频道',
          }),
          trailing: IconButton(
            tooltip: '解除频道屏蔽',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy
                ? null
                : () => _operate(
                    () => guard.updateRules(
                      SupervisionRules(
                        channels: guard.rules.channels.where(
                          (c) => c.key != channel.key,
                        ),
                        keywords: guard.rules.keywords,
                      ),
                    ),
                  ),
          ),
        ),
      const Divider(),
      ListTile(
        title: const Text('屏蔽关键词'),
        subtitle: const Text('按文字匹配名称、标题、分类及已有描述；统一大小写、全角和常见繁简字，不执行正则表达式。'),
        trailing: IconButton(
          tooltip: '添加屏蔽关键词',
          icon: const Icon(Icons.add),
          onPressed: _busy || guard.corrupted ? null : _addKeyword,
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final keyword in guard.rules.keywords)
            InputChip(
              label: Text(keyword),
              onDeleted: _busy
                  ? null
                  : () => _operate(
                      () => guard.updateRules(
                        SupervisionRules(
                          channels: guard.rules.channels,
                          keywords: guard.rules.keywords.where(
                            (w) => w != keyword,
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    ];
  }
}
