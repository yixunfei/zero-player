import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../data/release_calendar.dart';

final class ReleaseCalendarPage extends StatefulWidget {
  const ReleaseCalendarPage({super.key, required this.services});
  final AppServices services;
  @override
  State<ReleaseCalendarPage> createState() => _ReleaseCalendarPageState();
}

final class _ReleaseCalendarPageState extends State<ReleaseCalendarPage> {
  late final _repository = ReleaseCalendarRepository(
    widget.services.network,
    widget.services.db,
  );
  CancellationToken? _token;
  Future<void>? _pending;
  late final void Function() _removeHook;
  ReleaseCalendar? _data;
  bool _loading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _removeHook = widget.services.addCloseHook(_stop);
    _pending = _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    final token = _token = CancellationToken();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repository.load(
        refresh: refresh,
        cancellation: token,
      );
      if (mounted && !token.isCancelled) setState(() => _data = data);
    } catch (_) {
      if (mounted && !token.isCancelled) {
        setState(() => _error = '上映日历暂不可用，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stop() async {
    _token?.cancel();
    await _pending;
  }

  @override
  void dispose() {
    unawaited(_stop().whenComplete(_removeHook));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('上映日历'),
      actions: [
        IconButton(
          tooltip: '刷新上映日历',
          onPressed: _loading ? null : () => _pending = _load(refresh: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('来源：豆瓣即将上映。仅展示公开档期；可能含重映，日期以来源更新为准，不代表已上线播放。'),
        if (_data != null)
          Text(
            '${_data!.cached ? '本地成功缓存' : '刚刚同步'} · ${_data!.updatedAt.toLocal().toString().substring(0, 16)}',
          ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        for (final item in _data?.items ?? <FilmRelease>[])
          Card(
            child: ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: Text(item.title),
              subtitle: Text('${item.date} · ${item.genres}\n${item.region}'),
              onTap: () => _details(item),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
      ],
    ),
  );

  void _details(FilmRelease item) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('上映：${item.date}'),
            Text(item.genres),
            Text(item.region),
            const SizedBox(height: 12),
            SelectableText(item.url.toString()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: item.url.toString()));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已复制豆瓣来源链接')));
            }
          },
          child: const Text('复制来源链接'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
