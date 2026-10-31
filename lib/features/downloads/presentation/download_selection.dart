import '../../../core/platform/video_files.dart';
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
  String? destination;
  late bool multi = widget.services.settings.value.multiSourceDownload;
  List<Episode> get episodes => widget.item.lines[widget.line].episodes;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight: (MediaQuery.sizeOf(context).height - 32).clamp(0, 650),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(20),
          shrinkWrap: true,
          itemCount: episodes.length + 4,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Text(
                '下载选集 · ${widget.item.title}',
                style: Theme.of(context).textTheme.headlineSmall,
              );
            }
            if (index == 1) return _destination();
            if (index == 2) return _options();
            if (index == episodes.length + 3) return _actions();
            final i = index - 3;
            return CheckboxListTile(
              title: Text(episodes[i].label),
              value: selected.contains(i),
              subtitle: episodes[i].playable ? null : const Text('此地址不支持直接下载'),
              onChanged: busy || !episodes[i].playable
                  ? null
                  : (value) => setState(() {
                      if (value == true) {
                        selected.add(i);
                      } else {
                        selected.remove(i);
                      }
                    }),
            );
          },
        ),
      ),
    ),
  );

  Widget _options() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
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
                      if (episodes[i].playable && !selected.remove(i)) {
                        selected.add(i);
                      }
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
    ],
  );

  Widget _actions() => Wrap(
    alignment: WrapAlignment.end,
    spacing: 8,
    children: [
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
  );

  Widget _destination() => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.folder_outlined),
    title: const Text('保存位置'),
    subtitle: Text(
      destination ?? '应用离线库（可在下载页导出）',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: destination == null
        ? null
        : IconButton(
            tooltip: '使用应用离线库',
            icon: const Icon(Icons.close),
            onPressed: busy ? null : () => setState(() => destination = null),
          ),
    onTap: busy
        ? null
        : () => perform(context, () async {
            final path = await VideoFiles.chooseDirectory();
            if (mounted && path != null) {
              setState(() => destination = path);
            }
          }),
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
          destination: destination,
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
