import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/list_keyboard_navigation.dart';
import '../../../app/scroll_reveal_header.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:go_router/go_router.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../library/data/history_repository.dart';
import '../../sources/domain/video_source.dart';
import '../application/discovery_controller.dart';
import '../data/recommendation_repository.dart';
import '../data/catalog_discovery.dart';
import 'continue_watching.dart';
import 'discovery_hero.dart';
import 'discovery_toolbar.dart';
import '../../sources/presentation/block_source_button.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../sources/domain/source_order.dart';
import '../../sources/presentation/source_details_dialog.dart';

final class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key, required this.services});
  final AppServices services;
  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

final class _DiscoveryPageState extends State<DiscoveryPage> {
  final _feed = DiscoveryController();
  final _scroll = ScrollController();
  late Future<List<WatchEntry>> _history;
  List<VideoSource> _sources = [];
  String _type = 'movie';
  String _channel = '';
  late String _provider;
  late bool _filterAdult;
  bool _aggregate = false;
  bool _ready = false;
  final _showTop = ValueNotifier(false);
  String? _notice;
  int _sourceGeneration = 0;
  StreamSubscription<void>? _sourceChanges;
  StreamSubscription<void>? _historyChanges;

  @override
  void initState() {
    super.initState();
    final settings = widget.services.settings.value;
    _channel = settings.homeChannel;
    widget.services.searchSourceId = _channel.isEmpty ? null : _channel;
    _aggregate = settings.homeLayout == 'aggregate';
    _provider = settings.recommendation;
    _filterAdult = widget.services.contentPolicy.filterAdult;
    _history = widget.services.history.recentWorks();
    _historyChanges = widget.services.history.changes.listen((_) {
      if (mounted) {
        setState(() {
          _history = widget.services.history.recentWorks();
        });
      }
    });
    _feed.addListener(_changed);
    _scroll.addListener(_loadNearEnd);
    widget.services.settings.addListener(_settingsChanged);
    widget.services.contentPolicy.addListener(_policyChanged);
    _sourceChanges = widget.services.sources.changes.listen(
      (_) => unawaited(_syncSources()),
    );
    unawaited(_refresh());
  }

  List<DiscoverySection> get _visibleSections => [
    for (final section in _feed.sections)
      if (section.items.any(_recommendationAllowed))
        DiscoverySection(
          section.category,
          section.label,
          section.page,
          section.items.where(_recommendationAllowed).toList(),
        ),
  ];
  bool _recommendationAllowed(Recommendation item) =>
      (_channel.isEmpty ||
          widget.services.contentPolicy.sourceIdAllowed(_channel)) &&
      widget.services.contentPolicy.textAllowed(
        [item.title, item.subtitle, item.description].join(' '),
      );
  void _policyChanged() {
    _filterAdult = widget.services.contentPolicy.filterAdult;
    if (mounted) setState(() {});
    unawaited(_refresh());
  }

  void _settingsChanged() {
    final settings = widget.services.settings.value;
    if (settings.recommendation != _provider) {
      _provider = settings.recommendation;
      unawaited(_refresh());
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refresh() async {
    _resetScroll();
    final generation = ++_sourceGeneration;
    try {
      final sources = await widget.services.sources.all();
      final preferred = await widget.services.sources.preferredId(_channel);
      if (!mounted || generation != _sourceGeneration) return;
      _channel = preferred;
      _sources =
          sources
              .where(
                (s) =>
                    s.enabled &&
                    !s.suppressed &&
                    widget.services.contentPolicy.sourceAllowed(s),
              )
              .toList()
            ..sort(compareRecommendedSources);
      _notice = null;
      if (_channel.isNotEmpty && !_sources.any((s) => s.id == _channel)) {
        _channel = '';
        _notice = '默认频道已移除、停用或被过滤，本次使用精选推荐';
      }
      _ready = true;
      _history = widget.services.history.recentWorks();
      await _reload(discoverCategories: true);
    } catch (_) {
      if (!mounted || generation != _sourceGeneration) return;
      setState(() {
        _ready = true;
        _notice = '频道列表读取失败，请刷新重试';
      });
    }
  }

  Future<void> _reload({bool discoverCategories = false}) {
    widget.services.searchSourceId = _channel.isEmpty ? null : _channel;
    final source = _sources.where((s) => s.id == _channel).firstOrNull;
    final provider = _provider;
    final filter = _filterAdult;
    return _feed.reset(
      loader: (category, page, token) => source == null
          ? widget.services.recommendations.load(
              provider,
              type: category,
              page: page,
              cancellation: token,
            )
          : _loadCatalog(
              source,
              category,
              page: page,
              cancellation: token,
              filterAdult: filter,
            ),
      categories: source == null
          ? recommendationCategories(provider)
          : discoverCategories
          ? {'': '全部'}
          : _feed.categories,
      category: _type,
      aggregate: _aggregate,
      discoverCategories: source != null && discoverCategories,
    );
  }

  Future<void> _syncSources() async {
    final generation = _sourceGeneration;
    final sources = await widget.services.sources.all();
    final preferred = await widget.services.sources.preferredId(_channel);
    if (!mounted || generation != _sourceGeneration) return;
    final visible =
        sources
            .where(
              (s) =>
                  s.enabled &&
                  !s.suppressed &&
                  widget.services.contentPolicy.sourceAllowed(s),
            )
            .toList()
          ..sort(compareRecommendedSources);
    setState(() => _sources = visible);
    if (preferred != _channel) {
      _channel = preferred;
      await widget.services.settings.load();
      if (mounted) await _refresh();
      return;
    }
    if (_ready &&
        _channel.isNotEmpty &&
        !visible.any((s) => s.id == _channel)) {
      await _refresh();
    }
  }

  Future<Recommendations> _loadCatalog(
    VideoSource source,
    String category, {
    required int page,
    required CancellationToken cancellation,
    required bool filterAdult,
  }) async {
    final clock = Stopwatch()..start();
    try {
      final result = await discoverCatalog(
        source,
        widget.services.network,
        category,
        page: page,
        cancellation: cancellation,
        filterAdult: filterAdult,
        policy: widget.services.contentPolicy,
      );
      cancellation.check();
      await widget.services.sources.health(
        source.id,
        null,
        latencyMs: clock.elapsedMilliseconds,
      );
      return result;
    } catch (error) {
      if (!cancellation.isCancelled) {
        await widget.services.sources.health(
          source.id,
          error is RemoteFailure
              ? error
              : const RemoteFailure(FailureKind.invalid, '频道加载失败'),
        );
      }
      rethrow;
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!_feed.loading && !_feed.categories.containsKey(_type)) {
      _type = _feed.categories.keys.firstOrNull ?? '';
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadNearEnd();
    });
  }

  void _loadNearEnd() {
    _showTop.value = _scroll.hasClients && _scroll.offset > 500;
    if (_ready &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 480 &&
        _feed.canLoadAutomatically) {
      unawaited(_feed.loadMore());
    }
  }

  void _resetScroll() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<String> Function()? _synopsis(Recommendation item) =>
      _channel.isEmpty && _provider == 'douban' && item.id.isNotEmpty
      ? () => widget.services.synopses.get(item.id)
      : null;

  void _search(Recommendation item) => context.push(
    Uri(
      path: '/search',
      queryParameters: {'q': item.title, 'source': _channel},
    ).toString(),
  );

  Future<void> _saveDefault() => perform(
    context,
    () => widget.services.settings.update({
      'homeChannel': _channel,
      'homeLayout': _aggregate ? 'aggregate' : 'single',
    }),
    success: '已保存，下次进入首页使用此频道和布局',
  );

  @override
  void dispose() {
    unawaited(_sourceChanges?.cancel());
    unawaited(_historyChanges?.cancel());
    widget.services.settings.removeListener(_settingsChanged);
    widget.services.contentPolicy.removeListener(_policyChanged);
    _feed.removeListener(_changed);
    _feed.dispose();
    _scroll.dispose();
    _showTop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListKeyboardNavigation(
    controller: _scroll,
    child: Stack(
      children: [
        _content(),
        Positioned(
          right: 20,
          bottom: 20,
          child: ValueListenableBuilder<bool>(
            valueListenable: _showTop,
            builder: (_, show, _) => show
                ? FloatingActionButton.small(
                    heroTag: 'discovery-top',
                    tooltip: '返回顶部 (Ctrl+Home)',
                    onPressed: _returnToTop,
                    child: const Icon(Icons.vertical_align_top),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    ),
  );

  void _returnToTop() {
    if (!_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  Widget _content() => RefreshIndicator(
    onRefresh: _refresh,
    child: CustomScrollView(
      key: const ValueKey('discovery-scroll'),
      controller: _scroll,
      scrollCacheExtent: const ScrollCacheExtent.pixels(300),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          sliver: SliverToBoxAdapter(child: _header()),
        ),
        ScrollRevealHeader(
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: _menus(),
            ),
          ),
        ),
        SliverToBoxAdapter(child: ContinueWatching(history: _history)),
        if (_visibleSections.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            sliver: SliverToBoxAdapter(
              child: DiscoveryHero(
                item: _visibleSections.first.items.first,
                loadDescription: _synopsis(_visibleSections.first.items.first),
                onPlay: () => _search(_visibleSections.first.items.first),
              ),
            ),
          ),
        if (_feed.message != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_feed.message!),
            ),
          ),
        for (final section in _visibleSections) _section(section),
        if (_feed.hasFailures && _channel.isNotEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: BlockSourceButton(
                name:
                    _sources
                        .where((s) => s.id == _channel)
                        .firstOrNull
                        ?.displayName ??
                    '当前频道',
                onBlock: () async {
                  await widget.services.sources.setEnabled(_channel, false);
                  if (mounted) await _refresh();
                },
              ),
            ),
          ),
        SliverToBoxAdapter(child: _footer()),
      ],
    ),
  );

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('你的私人影院', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text('发现好故事，继续未完的旅程。', style: Theme.of(context).textTheme.bodyMedium),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => context.push('/calendar'),
          icon: const Icon(Icons.calendar_month),
          label: const Text('上映日历'),
        ),
      ),
      const SizedBox(height: 8),
      if (_notice != null) Text(_notice!),
    ],
  );

  Widget _menus() {
    final settings = widget.services.settings.value;
    final visible = _sources
        .where(widget.services.contentPolicy.sourceAllowed)
        .toList();
    final current = visible
        .where((source) => source.id == _channel)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DiscoveryToolbar(
          onSearch: () => context.push('/search'),
          sources: visible,
          channel: _channel,
          providerName: recommendationNames[_provider] ?? '精选推荐',
          isFavorite: current?.favorite ?? false,
          onFavorite: current == null
              ? null
              : () => perform(
                  context,
                  () => widget.services.sources.favorite(
                    current.id,
                    !current.favorite,
                  ),
                ),
          onDetails: current == null
              ? null
              : () => showSourceDetails(context, widget.services, current),
          aggregate: _aggregate,
          isDefault:
              settings.homeChannel == _channel &&
              settings.homeLayout == (_aggregate ? 'aggregate' : 'single'),
          onRefresh: () => unawaited(_refresh()),
          onSaveDefault: () => unawaited(_saveDefault()),
          onChannel: (value) {
            if (value.isNotEmpty &&
                !visible.any(
                  (s) =>
                      s.id == value &&
                      widget.services.contentPolicy.sourceAllowed(s),
                )) {
              return;
            }
            _sourceGeneration++;
            _channel = value;
            _type = value.isEmpty
                ? recommendationCategories(_provider).keys.first
                : '';
            _notice = null;
            _resetScroll();
            unawaited(_reload(discoverCategories: true));
          },
          onLayout: (value) {
            _aggregate = value;
            _resetScroll();
            unawaited(_reload());
          },
        ),
        const SizedBox(height: 12),
        if (_aggregate)
          const Text('按频道支持的全部分类轮流加载，相同作品去重。')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                for (final entry in _feed.categories.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: entry.key == _type,
                    onSelected: (_) {
                      _type = entry.key;
                      _resetScroll();
                      unawaited(_reload());
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _section(DiscoverySection section) => SliverMainAxisGroup(
    slivers: [
      if (_aggregate)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          sliver: SliverToBoxAdapter(
            child: Text(
              '${section.label}${section.page > 1 ? ' · 第 ${section.page} 页' : ''}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent:
                widget.services.platform.television ||
                    widget.services.settings.value.mode == 'television'
                ? 320
                : 230,
            childAspectRatio: .64,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
          ),
          itemCount: section.items.length,
          addAutomaticKeepAlives: false,
          itemBuilder: (_, i) {
            final item = section.items[i];
            return PosterCard(
              key: ValueKey(item.identity),
              title: item.title,
              poster: item.poster,
              subtitle: item.subtitle,
              description: item.description,
              loadDescription: _synopsis(item),
              onTap: () => _search(item),
            );
          },
        ),
      ),
    ],
  );

  Widget _footer() {
    if (!_ready || _feed.loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_feed.count == 0 && !_feed.hasMore) {
      return EmptyState(
        '搜索下一部好故事',
        _feed.message ?? '当前频道没有内容，可切换频道或直接搜索',
        action: FilledButton.icon(
          onPressed: () => context.push('/search'),
          icon: const Icon(Icons.search),
          label: const Text('搜索影片'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Center(
        child: Column(
          children: [
            Text(
              _feed.atLimit && _feed.hasMore
                  ? '已展示 ${_feed.count} 部 · 自动加载已暂停。继续加载会增加流量和列表内存；离屏封面会自动回收。'
                  : _feed.hasMore
                  ? '已展示 ${_feed.count} 部 · 滚动继续浏览'
                  : '已展示全部 ${_feed.count} 部',
            ),
            if (_feed.hasMore)
              TextButton.icon(
                onPressed: () => unawaited(
                  _feed.loadMore(
                    retry: true,
                    manual: true,
                    itemCount: widget.services.settings.value.manualLoadCount,
                  ),
                ),
                icon: const Icon(Icons.expand_more),
                label: Text(
                  _feed.hasFailures
                      ? '重试加载'
                      : '再加载 ${widget.services.settings.value.manualLoadCount} 部',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
