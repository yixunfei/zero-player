import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/list_keyboard_navigation.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../media/engine/media_kit_engine.dart';
import '../application/radio_controller.dart';
import '../data/radio_repository.dart';
import 'radio_player_controls.dart';

final class RadioPage extends StatefulWidget {
  const RadioPage({super.key, required this.services});
  final AppServices services;
  @override
  State<RadioPage> createState() => _RadioPageState();
}

final class _RadioPageState extends State<RadioPage> {
  final _controller = RadioController(() => MediaKitEngine(videoOutput: false));
  final _query = TextEditingController();
  final _scroll = ScrollController();
  CancellationToken? _request;
  RadioCatalog? _catalog;
  bool _loading = false;
  String? _error;
  String _group = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool refresh = false}) async {
    _request?.cancel();
    final token = _request = CancellationToken();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.services.radio.load(
        refresh: refresh,
        cancellation: token,
      );
      if (!mounted || token.isCancelled) return;
      setState(() {
        _catalog = result;
        _error = result.notice;
        if (!result.stations.any((station) => station.group == _group)) {
          _group = '';
        }
      });
    } catch (_) {
      if (mounted && !token.isCancelled) {
        setState(() => _error = '广播列表获取失败，请检查网络后刷新重试。');
      }
    } finally {
      if (mounted && !token.isCancelled) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _request?.cancel();
    _query.dispose();
    _scroll.dispose();
    unawaited(_controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _toolbar(),
      if (_loading) const LinearProgressIndicator(),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(error),
        ),
      Expanded(child: _stations()),
      RadioPlayerControls(controller: _controller),
    ],
  );

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '在线广播 · 实验阶段',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: '广播来源与说明',
              onPressed: _sourceInfo,
              icon: const Icon(Icons.info_outline),
            ),
            IconButton(
              tooltip: '刷新广播列表',
              onPressed: _loading ? null : () => _load(refresh: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '搜索电台',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: '清空电台搜索',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _query.clear();
                      setState(() {});
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<String>(
                key: ValueKey(_group),
                initialValue: _group,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '分组'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部')),
                  for (final group in {
                    for (final station in _catalog?.stations ?? [])
                      if (station.group.isNotEmpty) station.group,
                  })
                    DropdownMenuItem(
                      value: group,
                      child: Text(group, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _group = value ?? ''),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _stations() {
    final query = _query.text.trim().toLowerCase();
    final stations = (_catalog?.stations ?? [])
        .where(
          (station) =>
              (_group.isEmpty || station.group == _group) &&
              (query.isEmpty || station.name.toLowerCase().contains(query)),
        )
        .toList();
    if (stations.isEmpty) {
      return Center(
        child: Text(
          _loading
              ? '正在加载电台…'
              : _catalog == null
              ? '点击刷新获取内置广播列表'
              : '没有匹配的电台',
        ),
      );
    }
    return ListKeyboardNavigation(
      controller: _scroll,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => ListView.builder(
          controller: _scroll,
          itemCount: stations.length,
          itemBuilder: (context, index) {
            final station = stations[index];
            final selected = _controller.selected?.id == station.id;
            return ListTile(
              key: ValueKey('radio:${station.id}'),
              selected: selected,
              leading: Icon(
                selected && _controller.playing
                    ? Icons.graphic_eq
                    : Icons.radio_outlined,
              ),
              title: Text(
                station.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(station.group.isEmpty ? '网络广播' : station.group),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: () => _controller.select(station),
            );
          },
        ),
      ),
    );
  }

  void _sourceInfo() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('在线广播（实验）'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '内置列表由 popocoding/awesome-m3u 提供。首次进入时联网获取，成功列表缓存 24 小时；更新失败保留旧列表。',
            ),
            SizedBox(height: 12),
            SelectableText(builtinRadioUrl),
            SizedBox(height: 12),
            Text('电台由第三方提供，可能因网络、地域或源站调整不可用。资源版权归相关权利人；版权问题请联系对应内容提供方或列表维护方。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
