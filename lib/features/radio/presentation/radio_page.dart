import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_services.dart';
import '../../../app/list_keyboard_navigation.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../app/widgets.dart';
import '../application/radio_controller.dart';
import '../data/radio_repository.dart';
import 'radio_player_controls.dart';
import 'radio_subscriptions_dialog.dart';
import 'radio_toolbar.dart';
import 'radio_mini_player.dart';
import '../domain/radio_category.dart';
import '../../live/presentation/live_probe_dialog.dart';
import '../../live/domain/channel_identity.dart';
import '../../live/domain/live_channel.dart';
import '../../live/domain/live_health.dart';

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
  String _health = '全部状态';
  RadioCategory? _category;
  bool _playerExpanded = true;
  late final void Function() _removeCloseHook;

  @override
  void initState() {
    super.initState();
    _removeCloseHook = widget.services.addCloseHook(() async {
      _request?.cancel();
    });
    widget.services.contentPolicy.addListener(_policyChanged);
    unawaited(_load());
  }

  void _policyChanged() {
    if (mounted) {
      setState(() => _catalog = null);
      unawaited(_load());
    }
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
    widget.services.contentPolicy.removeListener(_policyChanged);
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
      _player(),
    ],
  );

  Widget _toolbar() => RadioToolbar(
    query: _query,
    groups: {
      for (final station in _catalog?.stations ?? [])
        if (station.group.isNotEmpty &&
            (_category == null || radioCategory(station) == _category))
          station.group,
    },
    group: _group,
    favoritesOnly: _favoritesOnly,
    loading: _loading,
    updatedAt: _catalog?.updatedAt,
    onGroup: (value) => setState(() => _group = value),
    onFavorites: (value) => setState(() => _favoritesOnly = value),
    onSearch: () => setState(() {}),
    onSubscriptions: _subscriptions,
    onProbe: _probe,
    health: _health,
    onHealth: (value) => setState(() => _health = value),
    onInfo: _sourceInfo,
    onRefresh: () => _load(refresh: true),
    category: _category,
    onCategory: (value) => setState(() {
      _category = value;
      _group = '';
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }),
    onCollapse: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    },
  );

  Widget _player() => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => _playerExpanded || !_controller.active
        ? RadioPlayerControls(
            controller: _controller,
            onCollapse: _controller.active
                ? () => setState(() => _playerExpanded = false)
                : null,
          )
        : RadioMiniPlayer(
            controller: _controller,
            onExpand: () => setState(() => _playerExpanded = true),
          ),
  );

  List<LiveChannel> _filteredStations() {
    final query = _query.text.trim().toLowerCase();
    final stations = (_catalog?.stations ?? [])
        .where(
          (station) =>
              widget.services.contentPolicy.channelAllowed(
                station,
                radio: true,
              ) &&
              (!_favoritesOnly || station.favorite) &&
              (_health == '全部状态' ||
                  _health == '已停用' && !station.health.enabled ||
                  _health == '有媒体响应' &&
                      station.health.enabled &&
                      station.health.availability ==
                          LiveAvailability.responding ||
                  _health == '未检测' &&
                      station.health.availability == LiveAvailability.unknown ||
                  _health == '待处理' &&
                      {
                        LiveAvailability.inconclusive,
                        LiveAvailability.unavailable,
                      }.contains(station.health.availability)) &&
              (_category == null || radioCategory(station) == _category) &&
              (_group.isEmpty || station.group == _group) &&
              channelMatchesQuery(station.name, query),
        )
        .toList();
    return stations;
  }

  Future<void> _probe() async {
    final stations = _filteredStations();
    if (stations.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => LiveProbeDialog(
        services: widget.services,
        channels: stations,
        enableResponding: _health == '已停用',
      ),
    );
    if (mounted) await _load();
  }

  Widget _stations() {
    final stations = _filteredStations();
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
                    : radioCategory(station) == RadioCategory.television
                    ? Icons.tv_outlined
                    : Icons.radio_outlined,
              ),
              title: Text(
                station.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  radioCategory(station).label,
                  if (station.group.isNotEmpty) station.group,
                  station.health.label,
                ].join(' · '),
              ),
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
              onTap: () {
                if (!station.health.enabled || station.health.removed) {
                  message(context, '此电台已停用，请检测并恢复后播放');
                  return;
                }
                setState(() => _playerExpanded = true);
                unawaited(_controller.select(station));
              },
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
