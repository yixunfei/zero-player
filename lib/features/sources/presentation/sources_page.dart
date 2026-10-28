import '../../supervision/presentation/sensitive_action.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../domain/video_source.dart';
import 'catalog_import.dart';
import 'source_actions.dart';
import 'source_batch_bar.dart';
import 'source_card.dart';
import 'source_details_dialog.dart';
import '../../supervision/presentation/content_blocked_dialog.dart';

final class SourcesPage extends StatefulWidget {
  const SourcesPage({super.key, required this.services});
  final AppServices services;
  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

final class _SourcesPageState extends State<SourcesPage> {
  final selected = <String>{};
  bool showRemoved = false;
  late Future<List<VideoSource>> sources;
  late Future<List<Map<String, Object?>>> subscriptions;
  late final StreamSubscription<void> changes;
  @override
  void initState() {
    super.initState();
    _load();
    changes = widget.services.sources.changes.listen((_) {
      if (mounted) setState(_load);
    });
  }

  void _load() {
    sources = widget.services.sources.all(includeSuppressed: showRemoved);
    subscriptions = widget.services.sources.subscriptions();
  }

  @override
  void dispose() {
    changes.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('视频源')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('手动添加'),
                ),
                OutlinedButton(
                  onPressed: _restoreBuiltins,
                  child: const Text('恢复内置默认'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      importDefaultCatalog(context, widget.services),
                  child: const Text('noimank 多仓候选'),
                ),
                OutlinedButton(
                  onPressed: () => importCatalog(context, widget.services),
                  child: const Text('订阅 / 多仓'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      importCatalog(context, widget.services, file: true),
                  child: const Text('导入文件'),
                ),
                OutlinedButton(
                  onPressed: () => exportSources(context, widget.services),
                  child: const Text('导出分享文件'),
                ),
                OutlinedButton(
                  onPressed: () => batchProbeSources(context, widget.services),
                  child: const Text('批量探活'),
                ),
                OutlinedButton(
                  onPressed: () => publishSources(context, widget.services),
                  child: const Text('发布公开链接'),
                ),
              ],
            ),
          ),
          Expanded(
            child: LoadView(
              future: sources,
              builder: (items) => ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _batchBar(items),
                  if (items.any((source) => source.endpoint.scheme == 'http'))
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'HTTP 明文来源：搜索词、观看内容及发给同源站点的请求头可能以明文传输。请优先使用可信 HTTPS 来源。',
                      ),
                    ),
                  if (items.isEmpty)
                    const EmptyState('添加你的第一个来源', '从候选库选择，或导入普通 CMS 接口'),
                  for (final source in items) _source(source),
                  const Divider(),
                  const ListTile(
                    title: Text('订阅快照'),
                    subtitle: Text('失败的列表保留旧数据；部分成功会单独提示，手动启停保持不变'),
                  ),
                  FutureBuilder(
                    future: subscriptions,
                    builder: (context, snapshot) => Column(
                      children: [
                        for (final row
                            in snapshot.data ?? <Map<String, Object?>>[])
                          _subscription(row),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _restoreBuiltins() => perform(context, () async {
    if (!await confirm(context, '恢复内置默认', '恢复内置来源的默认启停选择，收藏保持不变。此操作受监管密码保护。')) {
      return;
    }
    if (!mounted) return;
    await runSensitive(
      context,
      widget.services.supervision,
      SensitiveOperation.channels,
      () => widget.services.builtins.initialize(restore: true),
    );
  });

  Widget _batchBar(List<VideoSource> items) => SourceBatchBar(
    services: widget.services,
    items: items,
    selected: selected,
    onSelection: (value) {
      if (mounted) {
        setState(() {
          selected.clear();
          selected.addAll(value);
        });
      }
    },
    showRemoved: showRemoved,
    onShowRemoved: (value) => setState(() {
      showRemoved = value;
      selected.clear();
      _load();
    }),
  );

  Widget _source(VideoSource source) => SourceCard(
    source: source,
    repository: widget.services.sources,
    selected: selected.contains(source.id),
    onSelected: (value) => setState(() {
      if (value) {
        selected.add(source.id);
      } else {
        selected.remove(source.id);
      }
    }),
    onDetails: () => showSourceDetails(context, widget.services, source),
    onAction: (value) {
      switch (value) {
        case 'details':
          showSourceDetails(context, widget.services, source);
        case 'edit':
          _edit(source);
        case 'probe':
          _probe(source);
        case 'reset':
          perform(
            context,
            () => widget.services.sources.resetHealth(source.id),
          );
        case 'delete':
          _remove(source);
      }
    },
  );

  Widget _subscription(Map<String, Object?> row) => ListTile(
    title: Text(row['name'] as String),
    subtitle: Text(
      [
        row['error'] as String? ?? '已保存成功快照',
        if (row['paused'] == 1)
          (row['failures'] as int) >= 3 ? '失败自动暂停，手动刷新成功后恢复' : '手动暂停',
      ].join(' · '),
    ),
    leading: Switch(
      value: row['paused'] != 1,
      onChanged: (value) => perform(
        context,
        () => widget.services.sources.pauseSubscription(
          row['id'] as String,
          !value,
        ),
      ),
    ),
    trailing: Wrap(
      children: [
        IconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
          onPressed: () => perform(
            context,
            () => widget.services.subscriptions.refresh(row),
          ),
        ),
        IconButton(
          tooltip: '删除订阅',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (await confirm(context, '删除订阅', '此订阅独有的来源将从列表移除，共享来源和手动来源保留。') &&
                mounted) {
              await perform(
                context,
                () => widget.services.sources.removeSubscription(
                  row['id'] as String,
                ),
              );
            }
          },
        ),
      ],
    ),
  );

  Future<void> _edit([VideoSource? source]) => perform(context, () async {
    if (source != null &&
        !widget.services.contentPolicy.sourceAllowed(source)) {
      await showDialog<void>(
        context: context,
        builder: (_) => ContentBlockedDialog(
          supervised: widget.services.supervision.enabled,
        ),
      );
      return;
    }
    final input = await inputDialog(
      context,
      source == null ? '添加接口' : '编辑接口',
      ['名称', 'CMS 接口 URL', '请求头 JSON（可留空）', '分类：unknown / general / adult'],
      initial: [
        source?.name ?? '',
        source?.endpoint.toString() ?? '',
        source == null ? '' : jsonEncode(source.headers),
        source?.classification ?? 'unknown',
      ],
    );
    if (input == null) return;
    if (input[0].isEmpty ||
        !{'unknown', 'general', 'adult'}.contains(input[3])) {
      throw const FormatException('请填写名称和有效分类');
    }
    final headers = input[2].isEmpty
        ? <String, String>{}
        : Map<String, String>.from(jsonDecode(input[2]));
    if (!mounted) return;
    await runSensitive(
      context,
      widget.services.supervision,
      SensitiveOperation.channels,
      () async {
        final id = await widget.services.sources.saveManual(
          input[0],
          Uri.parse(input[1]),
          headers: headers,
          enabled: source?.enabled ?? true,
          classification: input[3],
          kind: source?.kind ?? 'cms',
        );
        if (source != null && source.id != id) {
          await widget.services.sources.suppress(source.id, true);
        }
      },
    );
  });
  Future<void> _probe(VideoSource source) => perform(
    context,
    () => runSensitive(
      context,
      widget.services.supervision,
      SensitiveOperation.channels,
      () => widget.services.sourceProbe.run(
        [source],
        concurrency: 1,
        applyPolicy: true,
      ),
    ),
  );
  Future<void> _remove(VideoSource source) async {
    await perform(
      context,
      () => widget.services.sources.suppress(source.id, true),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.services.contentPolicy.sourceAllowed(source)
              ? '已移除 ${source.name}'
              : '已移除受限频道',
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => perform(
            context,
            () => runSensitive(
              context,
              widget.services.supervision,
              SensitiveOperation.channels,
              () => widget.services.sources.suppress(source.id, false),
            ),
          ),
        ),
      ),
    );
  }
}
