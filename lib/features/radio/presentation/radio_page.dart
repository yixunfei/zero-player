import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/list_keyboard_navigation.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../app/widgets.dart';
import '../application/radio_controller.dart';
import '../data/radio_repository.dart';
import 'radio_player_controls.dart';
import 'radio_subscriptions_dialog.dart';
import 'radio_toolbar.dart';

final class RadioPage extends StatefulWidget {
  const RadioPage({super.key, required this.services});
  final AppServices services;
  @override
  State<RadioPage> createState() => _RadioPageState();
}

final class _RadioPageState extends State<RadioPage> {
  late final RadioController _controller = widget.services.radioPlayer;
  final _query = TextEditingController();
  final _scroll = ScrollController();
  CancellationToken? _request;
  RadioCatalog? _catalog;
  bool _loading = false;
  String? _error;
  String _group = '';
  bool _favoritesOnly = false;
  late final void Function() _removeCloseHook;

  @override
  void initState() {
    super.initState();
    _removeCloseHook = widget.services.addCloseHook(() async {
      _request?.cancel();
    });
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
      if (!refresh && result.needsRefresh) {
        unawaited(_load(refresh: true));
      }
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
    _removeCloseHook();
    _request?.cancel();
    _query.dispose();
    _scroll.dispose();
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

  Widget _toolbar() => RadioToolbar(
    query: _query,
    groups: {
      for (final station in _catalog?.stations ?? [])
        if (station.group.isNotEmpty) station.group,
    },
    group: _group,
    favoritesOnly: _favoritesOnly,
    loading: _loading,
    updatedAt: _catalog?.updatedAt,
    onGroup: (value) => setState(() => _group = value),
    onFavorites: (value) => setState(() => _favoritesOnly = value),
    onSearch: () => setState(() {}),
    onSubscriptions: _subscriptions,
    onInfo: _sourceInfo,
    onRefresh: () => _load(refresh: true),
  );

  Widget _stations() {
    final query = _query.text.trim().toLowerCase();
    final stations = (_catalog?.stations ?? [])
        .where(
          (station) =>
              (!_favoritesOnly || station.favorite) &&
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
              trailing: IconButton(
                tooltip: station.favorite ? '取消收藏电台' : '收藏电台',
                icon: Icon(station.favorite ? Icons.star : Icons.star_outline),
                onPressed: () => perform(context, () async {
                  await widget.services.radio.favorite(
                    station,
                    !station.favorite,
                  );
                  final catalog = _catalog;
                  if (catalog == null) return;
                  final updated = await widget.services.radio.withFavorites(
                    catalog.stations,
                  );
                  if (mounted) {
                    setState(
                      () => _catalog = RadioCatalog(
                        updated,
                        catalog.updatedAt,
                        notice: catalog.notice,
                        needsRefresh: catalog.needsRefresh,
                      ),
                    );
                  }
                }),
              ),
              onTap: () => _controller.select(station),
            );
          },
        ),
      ),
    );
  }

  Future<void> _subscriptions() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          RadioSubscriptionsDialog(repository: widget.services.radio),
    );
    if (mounted) await _load();
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
              '内置列表由 popocoding/awesome-m3u 提供。随应用附带成功快照，先显示本地列表；超过 24 小时后台更新，失败继续使用旧列表。支持自定义 M3U / TXT 订阅和收藏。成功更新同时保存到本地数据库和应用数据目录 radio_snapshots。',
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
