import 'package:flutter/material.dart';
import '../../../core/network/cancellation_token.dart';
import '../data/live_repository.dart';
import '../domain/live_channel.dart';

final class LiveScheduleDialog extends StatefulWidget {
  const LiveScheduleDialog({
    super.key,
    required this.repository,
    required this.channel,
  });
  final LiveRepository repository;
  final LiveChannel channel;
  @override
  State<LiveScheduleDialog> createState() => _LiveScheduleDialogState();
}

final class _LiveScheduleDialogState extends State<LiveScheduleDialog> {
  List<EpgProgram> items = [];
  bool loading = true;
  String? error;
  final cancellation = CancellationToken();
  @override
  void dispose() {
    cancellation.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final cached = await widget.repository.schedule(widget.channel);
      if (!mounted) return;
      setState(() => items = cached);
      if (refresh || cached.isEmpty) {
        await widget.repository.refreshSchedule(
          widget.channel,
          cancellation: cancellation,
        );
      }
      final result = await widget.repository.schedule(widget.channel);
      if (mounted) setState(() => items = result);
    } catch (_) {
      if (mounted) setState(() => error = '节目表更新失败，保留本地节目；可稍后重试。');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _time(DateTime time) => time.toLocal().toString().substring(0, 16);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AlertDialog(
      title: Text('${widget.channel.name} · 节目单'),
      content: SizedBox(
        width: 540,
        height: 420,
        child: Column(
          children: [
            if (loading) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            if (!loading && items.isEmpty)
              const Text(
                '暂无匹配节目。请在“管理订阅 / EPG”配置 XMLTV 地址；频道需要匹配 tvg-id，缺少标识时按名称唯一匹配。源站未提供节目表时无法展示。',
              ),
            if (items.isNotEmpty)
              Text(
                '本地时间 · ${items.first.matchedByName ? '按名称匹配' : '按 tvg-id 匹配'}',
              ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final current =
                      !now.isBefore(item.start) && now.isBefore(item.end);
                  return ListTile(
                    leading: Icon(current ? Icons.play_circle : Icons.schedule),
                    title: Text('${current ? '正在播出 · ' : ''}${item.title}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_time(item.start)} — ${_time(item.end)}'),
                        if (current)
                          LinearProgressIndicator(
                            value:
                                (now.difference(item.start).inSeconds /
                                        item.duration.inSeconds)
                                    .clamp(0, 1),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: loading ? null : () => _load(refresh: true),
          child: const Text('刷新节目表'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
