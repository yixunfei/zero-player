import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../sources/application/source_probe.dart';
import '../../sources/presentation/block_source_button.dart';
import '../domain/catalog_item.dart';

final class SourceChoices extends StatefulWidget {
  const SourceChoices({
    super.key,
    required this.services,
    required this.items,
    required this.onSelected,
    required this.onBlock,
    this.sourceNames = const {},
    this.sourceLabels = const {},
  });
  final AppServices services;
  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onSelected;
  final Future<void> Function(String) onBlock;
  final Map<String, String> sourceNames;
  final Map<String, String> sourceLabels;
  @override
  State<SourceChoices> createState() => _SourceChoicesState();
}

final class _SourceChoicesState extends State<SourceChoices> {
  late final SourceProbe _probe;
  final _tested = <String>{};
  final _blocked = <String>{};
  bool _loading = false;
  bool _selected = false;
  @override
  void initState() {
    super.initState();
    _probe = SourceProbe(widget.services.sources, widget.services.network);
    unawaited(_probeNew());
  }

  @override
  void didUpdateWidget(SourceChoices oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_probeNew());
  }

  Future<void> _probeNew() async {
    if (_loading || _selected || !mounted) return;
    final ids = widget.items.map((i) => i.sourceId).toSet().difference(_tested);
    if (ids.isEmpty) return;
    _loading = true;
    _tested.addAll(ids);
    try {
      final sources = await widget.services.sources.all();
      if (!mounted || _selected) return;
      await _probe.run(
        sources
            .where(
              (s) =>
                  ids.contains(s.id) &&
                  widget.services.contentPolicy.sourceAllowed(s),
            )
            .toList(),
        preserveStatuses: true,
        concurrency: widget.services.settings.value.probeConcurrency,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          for (final id in ids) {
            _probe.statuses[id] = '检测失败，可重新打开选择器重试';
          }
        });
      }
    } finally {
      _loading = false;
      if (mounted) unawaited(_probeNew());
    }
  }

  @override
  void dispose() {
    _probe.dispose();
    super.dispose();
  }

  void _select(CatalogItem item) {
    if (_selected || !widget.services.contentPolicy.itemAllowed(item)) return;
    _selected = true;
    _probe.cancel();
    widget.onSelected(item);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_probe, widget.services.contentPolicy]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 480;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('正在检测渠道接口延迟；API 可用不代表视频可播。播放线路会单独检测媒体响应。'),
            ),
            for (final item in widget.items)
              if (!_blocked.contains(item.sourceId) &&
                  widget.services.contentPolicy.itemAllowed(item))
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  minLeadingWidth: 0,
                  title: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${widget.sourceLabels[item.sourceId] ?? ''} ${widget.sourceNames[item.sourceId] ?? ''} · ${item.year} ${item.remarks} · ${_probe.statuses[item.sourceId] ?? '等待接口检测'}',
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _select(item),
                  trailing: BlockSourceButton(
                    name: '此来源',
                    compact: compact,
                    onBlock: () async {
                      await widget.onBlock(item.sourceId);
                      if (mounted) setState(() => _blocked.add(item.sourceId));
                    },
                  ),
                ),
          ],
        );
      },
    ),
  );
}
