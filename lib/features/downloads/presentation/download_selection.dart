import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../catalog/domain/catalog_item.dart';

Future<void> selectDownloads(
  BuildContext context,
  AppServices services,
  CatalogItem item,
  int line,
) => showDialog<void>(
  context: context,
  builder: (_) =>
      _DownloadSelection(services: services, item: item, line: line),
);

final class _DownloadSelection extends StatefulWidget {
  const _DownloadSelection({
    required this.services,
    required this.item,
    required this.line,
  });
  final AppServices services;
  final CatalogItem item;
  final int line;
  @override
  State<_DownloadSelection> createState() => _DownloadSelectionState();
}

final class _DownloadSelectionState extends State<_DownloadSelection> {
  final selected = <int>{};
  bool busy = false;
  late bool multi = widget.services.settings.value.multiSourceDownload;
  List<Episode> get episodes => widget.item.lines[widget.line].episodes;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text('下载选集 · ${widget.item.title}'),
      content: SizedBox(
        width: 540,
        height: 420,
        child: Column(
          children: [
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          selected.addAll([
                            for (var i = 0; i < episodes.length; i++)
                              if (episodes[i].playable) i,
                          ]);
                        }),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          for (var i = 0; i < episodes.length; i++) {
                            if (!episodes[i].playable) continue;
                            if (!selected.remove(i)) selected.add(i);
                          }
                        }),
                  child: const Text('反选'),
                ),
                TextButton(
                  onPressed: busy ? null : () => setState(selected.clear),
                  child: const Text('清空'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('允许多源并发'),
              subtitle: const Text('按整集分配来源；并发集数可在设置调整'),
              value: multi,
              onChanged: busy ? null : (value) => setState(() => multi = value),
            ),
            Text(
              widget.services.settings.value.autoDownloadFallback
                  ? '下载中断后自动寻找同作品同集的其他源，换源后重新下载整集。'
                  : '自动换源已关闭，可在设置中启用。',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: episodes.length,
                itemBuilder: (_, i) => CheckboxListTile(
                  title: Text(episodes[i].label),
                  value: selected.contains(i),
                  subtitle: episodes[i].playable
                      ? null
                      : const Text('此地址不支持直接下载'),
                  onChanged: busy || !episodes[i].playable
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            selected.add(i);
                          } else {
                            selected.remove(i);
                          }
                        }),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: busy || selected.isEmpty ? null : _enqueue,
          icon: const Icon(Icons.download_outlined),
          label: Text(busy ? '正在加入…' : '下载 ${selected.length} 集'),
        ),
      ],
    ),
  );

  Future<void> _enqueue() async {
    setState(() => busy = true);
    await perform(context, () async {
      final source = await widget.services.sources.find(widget.item.sourceId);
      await widget.services.settings.update({'multiSourceDownload': multi});
      final line = widget.item.lines[widget.line];
      final indices = selected.toList()..sort();
      for (final index in indices) {
        await widget.services.downloads.create(
          widget.item,
          line,
          episodes[index],
          source?.headers ?? {},
        );
        selected.remove(index);
      }
      widget.services.downloadScheduler.kick();
      if (mounted) {
        message(context, '已加入 ${indices.length} 集下载');
        Navigator.pop(context);
      }
    });
    if (mounted) setState(() => busy = false);
  }
}
