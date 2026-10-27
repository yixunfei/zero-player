import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../data/history_repository.dart';

final class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.services});
  final AppServices services;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

final class _HistoryPageState extends State<HistoryPage> {
  late Future<List<WatchEntry>> future;
  late final StreamSubscription<void> subscription;
  @override
  void initState() {
    super.initState();
    _load();
    subscription = widget.services.db.changes.listen((_) {
      if (mounted) setState(_load);
    });
  }

  void _load() {
    future = widget.services.history.all();
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoadView(
    future: future,
    builder: (items) => items.isEmpty
        ? const EmptyState('观看记录为空', '播放进度会自动保存在本机')
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    if (await confirm(context, '清空观看记录', '删除本机的观看记录和进度？') &&
                        context.mounted) {
                      await perform(context, widget.services.history.clear);
                    }
                  },
                  child: const Text('清空记录'),
                ),
              ),
              for (final entry in items)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(entry.title),
                    subtitle: Text(
                      '${entry.line} · ${entry.episode}\n${clockText(entry.position)} / ${clockText(entry.duration)}',
                    ),
                    isThreeLine: true,
                    onTap: () => context.push(
                      '/detail/${entry.sourceId}/${Uri.encodeComponent(entry.remoteId)}',
                    ),
                    trailing: IconButton(
                      tooltip: '删除记录',
                      icon: const Icon(Icons.close),
                      onPressed: () => perform(
                        context,
                        () => widget.services.history.remove(entry.id),
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );
}
