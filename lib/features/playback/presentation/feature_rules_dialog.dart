import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../app/widgets.dart';
import '../../../media/content_filter/fingerprints/feature_rule.dart';
import '../../supervision/presentation/sensitive_action.dart';
import '../../supervision/application/supervision_controller.dart';
import '../application/playback_controller.dart';
import 'feature_rule_dialog.dart';

Future<void> showFeatureRules(
  BuildContext context,
  PlaybackController controller,
) => perform(context, () async {
  SensitiveSession? session;
  try {
    final guard = controller.services.supervision;
    final allowed = await runSensitive(
      context,
      guard,
      SensitiveOperation.contentFilter,
      () async {
        session = guard.createSession(SensitiveOperation.contentFilter);
      },
      explanation: '进入后可连续管理特征，关闭管理窗口后重新锁定。',
    );
    if (!allowed || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _RulesDialog(controller, session!),
    );
  } finally {
    session?.close();
  }
});

final class _RulesDialog extends StatefulWidget {
  const _RulesDialog(this.controller, this.session);
  final PlaybackController controller;
  final SensitiveSession session;
  @override
  State<_RulesDialog> createState() => _RulesDialogState();
}

final class _RulesDialogState extends State<_RulesDialog> {
  late final String sourceId = widget.controller.request!.item.sourceId;
  late final String seriesKey = widget.controller.featureSeriesKey;
  bool _busy = false;
  String _scope = 'all';
  String _query = '';
  late Future<List<FeatureRule>> _rules = _load();
  Future<List<FeatureRule>> _load() async =>
      (await widget.controller.services.filterFeatures.list())
          .where(
            (rule) =>
                rule.sourceId == sourceId ||
                rule.appliesTo(source: sourceId, series: seriesKey),
          )
          .toList();

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await perform(context, () async {
        await widget.session.run(action);
        if (mounted) {
          setState(() {
            _rules = _load();
          });
        }
        await widget.controller.refreshFeatureRules();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('内容特征管理'),
    content: SizedBox(
      width: 580,
      height: 460,
      child: FutureBuilder<List<FeatureRule>>(
        future: _rules,
        builder: (context, snapshot) => ListView(
          children: [
            ..._header(),
            if (snapshot.hasError)
              Text('加载失败：${snapshot.error}')
            else if (!snapshot.hasData)
              const LinearProgressIndicator()
            else
              ..._ruleList(snapshot.data!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('完成'),
      ),
    ],
  );

  List<Widget> _header() => [
    ListenableBuilder(
      listenable: widget.controller,
      builder: (_, _) => Text(widget.controller.featureStatusSummary),
    ),
    const SizedBox(height: 8),
    TextField(
      decoration: const InputDecoration(
        labelText: '搜索特征名称',
        prefixIcon: Icon(Icons.search),
      ),
      onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
    ),
    Wrap(
      spacing: 8,
      children: [
        for (final option in const {
          'all': '全部',
          'channel': '频道',
          'series': '全剧',
          'disabled': '已停用',
        }.entries)
          ChoiceChip(
            label: Text(option.value),
            selected: _scope == option.key,
            onSelected: (_) => setState(() => _scope = option.key),
          ),
      ],
    ),
    const SizedBox(height: 8),
  ];

  List<Widget> _ruleList(List<FeatureRule> values) {
    if (values.isEmpty) return [const Text('尚无特征。播放中先标记特征起点，再标记终点并采集。')];
    final rules = values
        .where(
          (r) =>
              r.label.toLowerCase().contains(_query) &&
              (_scope == 'all' ||
                  _scope == r.scope.name ||
                  (_scope == 'disabled' && !r.enabled)),
        )
        .toList();
    if (rules.isEmpty) return [const Text('没有符合筛选条件的特征')];
    return rules.map(_tile).toList();
  }

  Widget _tile(FeatureRule rule) {
    final repository = widget.controller.services.filterFeatures;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rule.thumbnail.isNotEmpty)
              Image.memory(base64Decode(rule.thumbnail), height: 90),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(rule.label),
              subtitle: Text(
                '${featureModeLabel(rule.mode)} · 片段 ${rule.sampleMs / 1000} 秒 · ${rule.signatures.length} 个短特征\n'
                '${rule.scope == FeatureScope.channel ? '频道通用' : '全剧通用'} · '
                '${rule.appliesTo(source: sourceId, series: seriesKey) ? '适用此作品' : '不适用此作品'}\n'
                '前 ${rule.beforeMs / 1000} 秒 / 后 ${rule.afterMs / 1000} 秒',
              ),
              value: rule.enabled,
              onChanged: _busy
                  ? null
                  : (value) =>
                        _change(() => repository.setEnabled(rule, value)),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await editFeatureRule(
                            context,
                            widget.controller,
                            rule: rule,
                            authorization: widget.session,
                          );
                          if (mounted) {
                            setState(() {
                              _rules = _load();
                            });
                          }
                        },
                  child: const Text('预览 / 编辑'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _delete(rule),
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(FeatureRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除内容特征'),
        content: Text('删除「${rule.label}」后将停止匹配此样本。需要再次使用时须重新采集。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _change(
        () => widget.controller.services.filterFeatures.remove(rule.id),
      );
    }
  }
}
