import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../../core/platform/file_transfer.dart';
import '../application/subscription_service.dart';
import '../data/catalog_parser.dart';
import '../domain/source_catalog.dart';

Future<void> importCatalog(
  BuildContext context,
  AppServices services, {
  bool file = false,
  CatalogPreview? initial,
}) => perform(context, () async {
  CatalogPreview preview;
  if (initial != null) {
    preview = initial;
  } else if (file) {
    final text = await FileTransfer.readText(maxBytes: 2 * 1024 * 1024);
    if (text == null) return;
    final origin = Uri.parse('https://local-import.invalid/');
    preview = CatalogPreview(
      origin,
      text,
      const JsonSourceCatalogParser().parse(text, origin),
    );
  } else {
    final values = await inputDialog(context, '导入订阅 / 多仓', [
      '配置文件 URL',
    ], action: '预览');
    if (values == null) return;
    preview = await services.subscriptions.preview(Uri.parse(values.first));
  }
  if (!context.mounted) return;
  final selected =
      await showDialog<
        ({
          List<SourceCandidate> sources,
          List<LiveCatalogEntry> lives,
          List<CatalogReference> children,
          bool enabled,
        })
      >(
        context: context,
        builder: (_) => CatalogImportDialog(preview: preview),
      );
  if (selected == null) return;
  final chosen = CatalogPreview(
    preview.url,
    preview.text,
    SourceCatalog(
      sources: selected.sources,
      references: [],
      diagnostics: [],
      lives: selected.lives,
    ),
  );
  if (file) {
    await services.subscriptions.importLocal(
      chosen,
      enableNew: selected.enabled,
    );
  } else if (selected.sources.isNotEmpty || selected.lives.isNotEmpty) {
    await services.subscriptions.import(
      chosen,
      preview.url.host,
      enableNew: selected.enabled,
    );
  }
  var failures = 0;
  final children = await services.subscriptions.selectedChildren(
    selected.children,
    onFailure: (_, error) => failures++,
  );
  for (final child in children.where(
    (c) => c.catalog.sources.isNotEmpty || c.catalog.lives.isNotEmpty,
  )) {
    try {
      await services.subscriptions.import(
        child,
        child.url.host,
        enableNew: selected.enabled,
      );
    } catch (_) {
      failures++;
    }
  }
  if (context.mounted) {
    message(
      context,
      failures == 0 ? '导入完成。接口和播放可用性需单独检查' : '已保存成功的子仓，$failures 个子仓失败，可重新导入',
    );
  }
});

final class CatalogImportDialog extends StatefulWidget {
  const CatalogImportDialog({super.key, required this.preview});
  final CatalogPreview preview;
  @override
  State<CatalogImportDialog> createState() => _CatalogImportDialogState();
}

final class _CatalogImportDialogState extends State<CatalogImportDialog> {
  List<Widget> _liveChoices(SourceCatalog catalog) => [
    for (final entry in catalog.lives)
      CheckboxListTile(
        title: Text(entry.name),
        subtitle: Text(entry.url.host),
        value: lives.contains(entry),
        onChanged: (value) => setState(() {
          if (value == true) {
            lives.add(entry);
          } else {
            lives.remove(entry);
          }
        }),
      ),
  ];
  final lives = <LiveCatalogEntry>{};
  final sources = <SourceCandidate>{};
  final children = <CatalogReference>{};
  bool enabled = false;
  @override
  void initState() {
    super.initState();
    sources.addAll(widget.preview.catalog.sources);
    lives.addAll(widget.preview.catalog.lives);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.preview.catalog;
    return AlertDialog(
      title: const Text('检查导入内容'),
      content: SizedBox(
        width: 660,
        height: 470,
        child: ListView(
          children: [
            Text(
              '${catalog.lives.length} 个直播列表 · ${catalog.sources.length} 个点播接口 · ${catalog.references.length} 个子仓 · ${catalog.diagnostics.length} 个跳过项',
            ),
            const Text('导入不代表可播放。子仓仅在选中后展开；不执行 Spider、JAR 或脚本。'),
            SwitchListTile(
              title: const Text('启用本次新导入的接口'),
              value: enabled,
              onChanged: (v) => setState(() => enabled = v),
            ),
            for (final source in catalog.sources)
              CheckboxListTile(
                title: Text(source.name),
                subtitle: Text(source.endpoint.host),
                value: sources.contains(source),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    sources.add(source);
                  } else {
                    sources.remove(source);
                  }
                }),
              ),
            ..._liveChoices(catalog),
            for (final child in catalog.references)
              CheckboxListTile(
                title: Text(child.name),
                subtitle: const Text('选择展开此子仓及其下级配置'),
                value: children.contains(child),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    children.add(child);
                  } else {
                    children.remove(child);
                  }
                }),
              ),
            for (final diagnostic in catalog.diagnostics)
              ListTile(
                title: Text(diagnostic.name),
                subtitle: Text(diagnostic.reason),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: sources.isEmpty && children.isEmpty && lives.isEmpty
              ? null
              : () => Navigator.pop(context, (
                  sources: sources.toList(),
                  lives: lives.toList(),
                  children: children.toList(),
                  enabled: enabled,
                )),
          child: const Text('导入所选'),
        ),
      ],
    );
  }
}

Future<void> exportSources(
  BuildContext context,
  AppServices services,
) => perform(context, () async {
  final sources = await services.sources.all();
  final output = const JsonEncoder.withIndent('  ').convert({
    'sources': [
      for (final source in sources)
        {
          'name': source.name,
          'kind': source.kind,
          'url': source.endpoint
              .replace(query: '', userInfo: '', fragment: '')
              .toString(),
          'enabled': false,
        },
    ],
  });
  if (!context.mounted) return;
  if (!await confirm(
    context,
    '导出可分享的源配置',
    '将导出 ${sources.length} 个接口，默认停用，移除 Headers 和 URL 查询参数。带鉴权参数的源需要接收者自行配置。\n\n文件保存到你选择的位置，不会自动上传。',
  )) {
    return;
  }
  await FileTransfer.saveText('zero-player-sources.json', output);
});
