import '../../supervision/presentation/sensitive_action.dart';
import 'package:flutter/material.dart';
import '../../../app/widgets.dart';
import '../../../core/network/cancellation_token.dart';
import '../data/radio_repository.dart';

final class RadioSubscriptionsDialog extends StatefulWidget {
  const RadioSubscriptionsDialog({super.key, required this.repository});
  final RadioRepository repository;
  @override
  State<RadioSubscriptionsDialog> createState() =>
      _RadioSubscriptionsDialogState();
}

typedef _SubscriptionRow = ({
  RadioSubscription subscription,
  DateTime? updatedAt,
});

final class _RadioSubscriptionsDialogState
    extends State<RadioSubscriptionsDialog> {
  final _token = CancellationToken();
  late Future<List<_SubscriptionRow>> _rows = _load();
  bool _busy = false;

  Future<List<_SubscriptionRow>> _load() async => Future.wait([
    for (final subscription in await widget.repository.subscriptions())
      _row(subscription),
  ]);

  Future<_SubscriptionRow> _row(RadioSubscription subscription) async => (
    subscription: subscription,
    updatedAt: (await widget.repository.snapshots.read(
      subscription,
    ))?.updatedAt,
  );

  @override
  void dispose() {
    _token.cancel();
    super.dispose();
  }

  Future<void> _operate(
    Future<void> Function() action, {
    bool sensitive = false,
  }) => perform(context, () async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await runSensitive(
        context,
        widget.repository.policy?.supervision,
        SensitiveOperation.channels,
        action,
        needed: sensitive,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _rows = _load();
        });
      }
    }
  });

  Future<void> _add() async {
    final input = await inputDialog(context, '添加广播订阅', [
      '名称',
      'M3U / TXT HTTP(S) 地址',
    ]);
    if (input == null || !mounted) return;
    await _operate(
      () => widget.repository.saveSubscription(
        input[0],
        Uri.parse(input[1]),
        cancellation: _token,
      ),
      sensitive: true,
    );
  }

  Future<void> _remove(RadioSubscription subscription) async {
    if (!await confirm(context, '删除广播订阅', '移除此订阅，保留本地成功快照与收藏；重新添加相同地址可以恢复。')) {
      return;
    }
    if (mounted) {
      await _operate(
        () => widget.repository.removeSubscription(subscription.id),
      );
    }
  }

  Future<void> _refresh(RadioSubscription subscription) => _operate(() async {
    final result = await widget.repository.refreshSubscription(
      subscription,
      cancellation: _token,
    );
    if (mounted) {
      message(
        context,
        result.notice ?? '同步成功，${result.stations.length} 个电台已保存到本地',
      );
    }
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('广播订阅'),
    content: SizedBox(
      width: 650,
      height: 400,
      child: Column(
        children: [
          const Text('只用校验通过的列表更新成功快照；失败不会清空旧列表。'),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: LoadView(
              future: _rows,
              builder: (rows) => ListView(
                children: [
                  if (rows.isEmpty)
                    const ListTile(title: Text('暂无广播订阅，请添加或恢复内置列表')),
                  for (final row in rows) _tile(row),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy
            ? null
            : () => _operate(
                () => widget.repository.saveSubscription(
                  '内置广播',
                  Uri.parse(builtinRadioUrl),
                  cancellation: _token,
                ),
                sensitive: true,
              ),
        child: const Text('恢复内置订阅'),
      ),
      FilledButton.icon(
        onPressed: _busy ? null : _add,
        icon: const Icon(Icons.add),
        label: const Text('添加订阅'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );

  Widget _tile(_SubscriptionRow row) {
    final subscription = row.subscription;
    return ListTile(
      title: Text(subscription.name),
      subtitle: Text(
        '${subscription.url}\n成功快照：${row.updatedAt?.toLocal().toString().substring(0, 16) ?? '暂无'}',
      ),
      isThreeLine: true,
      leading: Switch(
        value: subscription.enabled,
        onChanged: _busy
            ? null
            : (value) => _operate(
                () => widget.repository.setEnabled(subscription.id, value),
                sensitive: value,
              ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '刷新广播订阅',
            onPressed: _busy ? null : () => _refresh(subscription),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '删除广播订阅',
            onPressed: _busy ? null : () => _remove(subscription),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
