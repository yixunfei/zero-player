import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../data/book_store.dart';
import '../data/books_repository.dart';
import '../domain/book.dart';
import '../domain/legado_source.dart';
import 'book_category_picker.dart';
import 'book_cover.dart';
import 'book_source_favorite.dart';

final class BookDiscoveryView extends StatefulWidget {
  const BookDiscoveryView({
    super.key,
    required this.repository,
    required this.kind,
    required this.sources,
    required this.active,
    required this.onOpen,
    required this.onSearch,
    required this.onSourceFavorite,
    required this.onManage,
  });

  final BooksRepository repository;
  final BookKind kind;
  final List<BookSourceEntry>? sources;
  final bool active;
  final void Function(Book, {bool direct}) onOpen;
  final void Function(String query, String? sourceId, bool favorites) onSearch;
  final void Function(String id, bool favorite) onSourceFavorite;
  final VoidCallback onManage;

  @override
  State<BookDiscoveryView> createState() => _BookDiscoveryViewState();
}

final class _BookDiscoveryViewState extends State<BookDiscoveryView> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _results = <String, List<Book>>{};
  final _failures = <String>{};
  final _resultOrder = <String>[];
  final _recommended = <Book>[];
  final _recommendedIds = <String>{};
  CancellationToken? _token;
  String? _sourceId, _categorySource, _error;
  bool _favorites = false, _busy = false, _needsLoad = true;
  bool _direct = false;
  bool _aggregate = false, _preferencesReady = false;
  bool _channelsOnly = false;
  Set<String> _hidden = {};
  String? _genre;
  bool get _showChannelPreviews => _aggregate || widget.kind == BookKind.audio;
  String get _directKey => 'books_discovery_direct:${widget.kind.name}';
  String get _preferenceKey => 'books_discovery_hidden:${widget.kind.name}';
  int _page = 1, _completed = 0, _total = 0;
  List<LegadoCategory> _categories = [];
  LegadoCategory? _category;

  List<BookSourceEntry> _enabled = const [];
  BookSourceEntry? get _source =>
      _enabled.where((entry) => entry.source.id == _sourceId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _updateSources();
    unawaited(_readPreferences());
  }

  Future<void> _readPreferences() async {
    try {
      final value = await widget.repository.store.read(_preferenceKey);
      final direct = await widget.repository.store.read(_directKey);
      if (!mounted) return;
      if (value is List) _hidden = value.whereType<String>().toSet();
      _direct = direct == true;
    } on Exception {
      // Use defaults if the saved display preference cannot be read.
    } finally {
      if (mounted) setState(() => _preferencesReady = true);
      if (mounted) _loadIfReady();
    }
  }

  @override
  void didUpdateWidget(BookDiscoveryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.sources, oldWidget.sources)) {
      final before = _source?.source;
      final previous = _discoverySources;
      _updateSources();
      final current = _discoverySources;
      if (widget.sources != null &&
          oldWidget.sources != null &&
          sameBookDiscoverySources(current, previous)) {
        _loadIfReady();
        return;
      }
      _token?.cancel();
      _busy = false;
      _results.clear();
      _resultOrder.clear();
      _recommended.clear();
      _recommendedIds.clear();
      _failures.clear();
      _error = null;
      if (_source?.source.id != before?.id || _source != null) {
        _resetCategories();
      }
      _needsLoad = true;
    }
    _loadIfReady();
  }

  List<BookSourceEntry> get _discoverySources {
    if (_source case final entry?) return [entry];
    final eligible = _enabled.where(
      (entry) =>
          !_hidden.contains(entry.source.id) &&
          (!_favorites || entry.favorite) &&
          entry.source.hasDiscovery,
    );
    final prioritized = [
      ...eligible.where((entry) => entry.favorite),
      ...eligible.where((entry) => !entry.favorite),
    ];
    final included =
        (!_aggregate && _hidden.isEmpty ? prioritized.take(8) : prioritized)
            .map((entry) => entry.source.id)
            .toSet();
    return eligible
        .where((entry) => included.contains(entry.source.id))
        .toList();
  }

  void _updateSources() {
    final enabled =
        widget.sources?.where((entry) => entry.enabled).toList() ?? [];
    _enabled = enabled;
    if (_source == null) _sourceId = null;
  }

  void _loadIfReady() {
    if (_preferencesReady &&
        widget.sources != null &&
        widget.active &&
        _needsLoad) {
      unawaited(_load(page: _page));
    }
  }

  void _resetCategories() {
    _categorySource = null;
    _categories = [];
    _category = null;
    _page = 1;
  }

  Future<void> _load({int? page}) async {
    _token?.cancel();
    final token = _token = CancellationToken();
    setState(() {
      _busy = true;
      _needsLoad = false;
      _error = null;
      _page = page ?? 1;
      _completed = _total = 0;
      _results.clear();
      _resultOrder.clear();
      _recommended.clear();
      _recommendedIds.clear();
      _failures.clear();
      _genre = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.minScrollExtent);
    final sourceId = _sourceId;
    final sourceIds = _discoverySources.map((entry) => entry.source.id).toSet();
    try {
      if (sourceId != null && _categorySource != sourceId) {
        final categories = await widget.repository.categories(
          widget.kind,
          sourceId,
          token,
        );
        if (!mounted || token.isCancelled) return;
        setState(() {
          _categorySource = sourceId;
          _categories = categories;
          _category = categories.firstOrNull;
        });
      }
      await widget.repository.find(
        widget.kind,
        '',
        token,
        sourceId: sourceId,
        sourceIds: sourceId == null ? sourceIds : null,
        category: _category,
        page: _page,
        onProgress: (update) {
          if (!mounted || token.isCancelled) return;
          setState(() {
            _completed = update.completed;
            _total = update.total;
            final id = update.sourceId;
            if (id != null) {
              _results[id] = update.books;
              if (update.books.isNotEmpty) _resultOrder.add(id);
              if (update.failed) _failures.add(id);
            }
            // Append late responses so the visible rows keep their positions.
            if (id != null) {
              _appendRecommendations(update.books.take(12));
            }
          });
        },
      );
    } on FormatException catch (error) {
      if (mounted && !token.isCancelled) setState(() => _error = error.message);
    } on RemoteFailure catch (error) {
      if (mounted && !token.isCancelled) setState(() => _error = error.message);
    } on Exception {
      if (mounted && !token.isCancelled) setState(() => _error = '无法加载作品，请重试');
    } finally {
      if (mounted && identical(_token, token)) setState(() => _busy = false);
    }
  }

  Future<void> _setHidden(Set<String> ids, {bool reload = true}) async {
    setState(() => _hidden = ids);
    await widget.repository.store.write(_preferenceKey, ids.toList());
    if (mounted && reload) await _load();
  }

  Future<void> _pickVisibleSources() async {
    final selected = Set<String>.of(_hidden);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('发现页显示渠道'),
          content: SizedBox(
            width: 460,
            height: MediaQuery.sizeOf(context).height * .48,
            child: ListView.builder(
              itemCount: _enabled.length,
              itemBuilder: (_, index) {
                final source = _enabled[index].source;
                return CheckboxListTile(
                  title: Text(source.name),
                  value: !selected.contains(source.id),
                  onChanged: (value) => update(() {
                    if (value == true) {
                      selected.remove(source.id);
                    } else {
                      selected.add(source.id);
                    }
                  }),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (mounted && confirmed == true) await _setHidden(selected);
  }

  void _chooseSource(String? id) {
    if (id == null) _search.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _sourceId = id;
      _channelsOnly = false;
      _resetCategories();
    });
    unawaited(_load());
  }

  Future<void> _pickSource() async {
    final choice = await showDialog<({String? id})>(
      context: context,
      builder: (context) =>
          _ChannelPicker(entries: _enabled, selected: _sourceId),
    );
    if (mounted && choice != null) _chooseSource(choice.id);
  }

  Future<void> _pickCategory() async {
    final result = await showBookCategoryPicker(
      context,
      _categories,
      _category,
    );
    if (mounted && result != null) _selectCategory(result);
  }

  void _selectCategory(LegadoCategory category) {
    if (category == _category) return;
    setState(() => _category = category);
    unawaited(_load());
  }

  void _submitSearch() {
    final query = _search.text.trim();
    if (query.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onSearch(query, _sourceId, _sourceId == null && _favorites);
  }

  Future<void> _openMode() async {
    final direct = await showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('渠道书单点击方式'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_direct ? '聚合搜索' : '聚合搜索（当前）'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_direct ? '打开当前渠道（当前）' : '打开当前渠道'),
          ),
        ],
      ),
    );
    if (!mounted || direct == null || direct == _direct) return;
    await widget.repository.store.write(_directKey, direct);
    if (mounted) setState(() => _direct = direct);
  }

  Widget _favoriteButton(BookSourceEntry entry) => BookSourceFavorite(
    key: ValueKey(entry.source.id),
    repository: widget.repository,
    entry: entry,
    onChanged: (value) => widget.onSourceFavorite(entry.source.id, value),
  );

  @override
  void dispose() {
    _token?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sources == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth < 620 ? 16.0 : 26.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(gutter),
            Expanded(
              child: CustomScrollView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(child: _browseHeader(gutter)),
                  ..._content(gutter, constraints.maxWidth),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _returnToTop() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(position.minScrollExtent);
    } else {
      unawaited(
        _scroll.animateTo(
          position.minScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _toggleChannelsOnly() {
    setState(() => _channelsOnly = !_channelsOnly);
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.minScrollExtent);
  }

  Widget _toolbar(double gutter) => Padding(
    padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 8),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _search,
            maxLength: 2048,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submitSearch(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.kind == BookKind.audio ? '搜索作品' : '搜书名、作者或书籍链接',
              counterText: '',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          tooltip: '搜索',
          icon: const Icon(Icons.search),
          onPressed: _search.text.trim().isEmpty ? null : _submitSearch,
        ),
        if (_source == null)
          IconButton(
            tooltip: _channelsOnly ? '展开全部书单' : '折叠书单，仅显示渠道',
            isSelected: _channelsOnly,
            onPressed: _toggleChannelsOnly,
            icon: const Icon(Icons.unfold_less),
            selectedIcon: const Icon(Icons.unfold_more),
          ),
        IconButton(
          tooltip: '返回顶部',
          onPressed: _returnToTop,
          icon: const Icon(Icons.vertical_align_top),
        ),
      ],
    ),
  );

  Widget _browseHeader(double gutter) {
    final theme = Theme.of(context);
    final source = _source?.source;
    final status = _busy
        ? (_total == 0 ? '正在加载…' : '$_completed / $_total 个渠道')
        : _failures.isEmpty
        ? null
        : '${_failures.length} 个渠道加载失败';
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: _pickSource,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hub_outlined, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            source?.name ?? (_aggregate ? '聚合渠道' : '精选推荐'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              if (source == null)
                IconButton(
                  tooltip: '选择发现渠道',
                  onPressed: _pickVisibleSources,
                  icon: const Icon(Icons.checklist),
                ),
              if (source == null)
                IconButton(
                  tooltip: _favorites ? '显示全部渠道' : '仅收藏源',
                  isSelected: _favorites,
                  icon: const Icon(Icons.star_border),
                  selectedIcon: const Icon(Icons.star),
                  onPressed: () {
                    setState(() => _favorites = !_favorites);
                    unawaited(_load());
                  },
                ),
              if (_source case final BookSourceEntry entry)
                _favoriteButton(entry),
              if (source != null || _aggregate)
                IconButton(
                  tooltip: '渠道书单点击方式',
                  onPressed: _openMode,
                  icon: const Icon(Icons.settings_outlined),
                ),
              IconButton(
                tooltip: '刷新当前页面',
                onPressed: _busy ? null : () => _load(page: _page),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(status, style: theme.textTheme.bodySmall),
            ),
          if (_categories.isNotEmpty) _categoryBar(),
          if (source == null && widget.kind == BookKind.text && !_channelsOnly)
            _recommendationControls(),
        ],
      ),
    );
  }

  Widget _categoryBar() {
    final category = _category!;
    final index = _categories.indexOf(category);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final item in _categories.take(6))
            if (item.address.isNotEmpty)
              ChoiceChip(
                label: Text(
                  bookCategoryLabel(item, _categories.indexOf(item)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: item == category,
                onSelected: (_) => _selectCategory(item),
              ),
          if (_categories.length > 6)
            ActionChip(
              avatar: const Icon(Icons.grid_view, size: 16),
              label: Text(
                _categories.take(6).contains(category)
                    ? '全部分类'
                    : bookCategoryLabel(category, index),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: _pickCategory,
            ),
          if (category.paginated)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '上一页',
                  onPressed: _busy || _page == 1
                      ? null
                      : () => _load(page: _page - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('第 $_page 页'),
                IconButton(
                  tooltip: '下一页',
                  onPressed: _busy || (_results[_sourceId]?.isEmpty ?? true)
                      ? null
                      : () => _load(page: _page + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _appendRecommendations(Iterable<Book> books) {
    if (_source != null || _showChannelPreviews) return;
    for (final book in books) {
      if (_recommendedIds.add(
        '${bookIdentity(book.title)}:${bookIdentity(book.author)}',
      )) {
        _recommended.add(book);
      }
    }
  }

  Iterable<BookSourceEntry> get _orderedResults sync* {
    final byId = {for (final entry in _enabled) entry.source.id: entry};
    for (final id in _resultOrder) {
      if (byId[id] case final entry?) yield entry;
    }
  }

  Widget _recommendationControls() {
    final genres = _recommended
        .map((book) => book.category)
        .where((label) => label.isNotEmpty)
        .toSet()
        .take(80)
        .toList();
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (value, label) in const [(false, '推荐'), (true, '按渠道聚合')])
          ChoiceChip(
            label: Text(label),
            selected: _aggregate == value,
            onSelected: (_) {
              if (_aggregate == value) return;
              setState(() => _aggregate = value);
              unawaited(_load());
            },
          ),
        if (!_aggregate && genres.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: DropdownButton<String>(
              isExpanded: true,
              value: genres.contains(_genre) ? _genre : '',
              items: [
                const DropdownMenuItem(value: '', child: Text('全部分类')),
                for (final genre in genres)
                  DropdownMenuItem(
                    value: genre,
                    child: Text(genre, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _genre = value),
            ),
          ),
      ],
    );
  }

  List<Widget> _content(double gutter, double width) {
    final source = _source;
    if (source == null && _channelsOnly) return [_channelDirectory(gutter)];
    final sections = _orderedResults
        .where(
          (entry) =>
              _results[entry.source.id]?.isNotEmpty == true &&
              (source != null ||
                  (!_hidden.contains(entry.source.id) &&
                      (!_favorites || entry.favorite))),
        )
        .toList();
    if (sections.isEmpty) return [_empty(gutter)];
    if (source == null && !_showChannelPreviews) {
      return [
        _grid(
          _recommended
              .where(
                (book) =>
                    _genre == null ||
                    _genre!.isEmpty ||
                    book.category == _genre,
              )
              .toList(),
          gutter,
          width,
        ),
      ];
    }
    if (source != null) {
      return [_grid(_results[source.source.id] ?? const [], gutter, width)];
    }
    return [
      SliverList.builder(
        findChildIndexCallback: (key) {
          final index = sections.indexWhere(
            (entry) => entry.source.id == (key as ValueKey<String>).value,
          );
          return index < 0 ? null : index;
        },
        itemCount: sections.length,
        itemBuilder: (context, index) {
          final entry = sections[index];
          final books = _results[entry.source.id]!;
          return _channelSection(entry, books, gutter);
        },
      ),
      SliverToBoxAdapter(
        child: Center(
          child: TextButton.icon(
            onPressed: _pickSource,
            icon: const Icon(Icons.hub_outlined),
            label: const Text('浏览更多渠道'),
          ),
        ),
      ),
    ];
  }

  Widget _channelDirectory(double gutter) {
    final channels = _enabled
        .where(
          (entry) =>
              !_hidden.contains(entry.source.id) &&
              (!_favorites || entry.favorite),
        )
        .toList();
    if (channels.isEmpty) return _empty(gutter);
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      sliver: SliverList.builder(
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final entry = channels[index];
          return ListTile(
            key: ValueKey(entry.source.id),
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(
              entry.source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _chooseSource(entry.source.id),
          );
        },
      ),
    );
  }

  Widget _grid(List<Book> books, double gutter, double width) {
    final count = ((width - 2 * gutter + 14) / 162).floor().clamp(2, 7);
    final cardWidth = (width - 2 * gutter - (count - 1) * 14) / count;
    final textHeight = MediaQuery.textScalerOf(context).scale(13) * 3 + 18;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 24),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          mainAxisExtent: cardWidth * 1.44 + textHeight,
          crossAxisSpacing: 14,
          mainAxisSpacing: 18,
        ),
        itemCount: books.length,
        findChildIndexCallback: (key) {
          final index = books.indexWhere(
            (book) => book.id == (key as ValueKey<String>).value,
          );
          return index < 0 ? null : index;
        },
        itemBuilder: (context, index) => _card(books[index]),
      ),
    );
  }

  Widget _empty(double gutter) {
    final source = _source?.source;
    final message =
        _error ??
        (_busy
            ? '正在加载作品…'
            : _enabled.isEmpty
            ? '启用书源后即可在这里找书'
            : _favorites &&
                  source == null &&
                  !_enabled.any((entry) => entry.favorite)
            ? '还没有收藏的启用渠道'
            : _failures.isNotEmpty
            ? '当前渠道未返回可用作品'
            : source != null && !source.hasDiscovery
            ? source.hasSearch
                  ? '输入书名或作者搜索此渠道'
                  : '粘贴此渠道的书籍链接打开作品'
            : '暂无可浏览作品，试试其他渠道或按书名搜索');
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: EdgeInsets.all(gutter),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (_enabled.isEmpty)
              TextButton(onPressed: widget.onManage, child: const Text('管理书源'))
            else if (!_busy && (_error != null || _failures.isNotEmpty))
              TextButton(
                onPressed: () => _load(page: _page),
                child: const Text('重试'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _channelSection(
    BookSourceEntry entry,
    List<Book> books,
    double gutter,
  ) {
    final theme = Theme.of(context);
    final source = entry.source;
    final preview = books.take(10).toList();
    final height = 190 + MediaQuery.textScalerOf(context).scale(13) * 3 + 18;
    return Padding(
      key: ValueKey(source.id),
      padding: const EdgeInsets.only(top: 12, bottom: 14),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontFamily: 'NotoSerifSC',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _chooseSource(source.id),
                  icon: const Icon(Icons.chevron_right, size: 18),
                  iconAlignment: IconAlignment.end,
                  label: const Text('浏览渠道'),
                ),
                _favoriteButton(entry),
                IconButton(
                  tooltip: '从发现页隐藏此渠道',
                  icon: const Icon(Icons.visibility_off_outlined),
                  onPressed: () =>
                      _setHidden({..._hidden, source.id}, reload: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: height,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  ...ScrollConfiguration.of(context).dragDevices,
                  PointerDeviceKind.mouse,
                },
              ),
              child: ListView.separated(
                primary: false,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: gutter),
                itemCount: preview.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, index) =>
                    SizedBox(width: 134, child: _card(preview[index])),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Book book) => _DiscoveryBookCard(
    key: ValueKey(book.id),
    book: book,
    repository: widget.repository,
    onTap: () => widget.onOpen(
      book,
      direct: _direct && (_sourceId != null || _aggregate),
    ),
  );
}

final class _ChannelPicker extends StatefulWidget {
  const _ChannelPicker({required this.entries, required this.selected});
  final List<BookSourceEntry> entries;
  final String? selected;

  @override
  State<_ChannelPicker> createState() => _ChannelPickerState();
}

final class _ChannelPickerState extends State<_ChannelPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sources = widget.entries
        .where(
          (entry) =>
              '${entry.source.name} ${entry.source.endpoint.host} ${entry.group}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();
    return AlertDialog(
      title: const Text('选择渠道'),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * .49,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '筛选渠道',
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            if (_query.isEmpty)
              ListTile(
                leading: const Icon(Icons.hub_outlined),
                selected: widget.selected == null,
                title: const Text('回到推荐与聚合'),
                onTap: () => Navigator.pop(context, (id: null as String?)),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: sources.length,
                itemBuilder: (context, index) {
                  final entry = sources[index];
                  final source = entry.source;
                  return ListTile(
                    selected: widget.selected == source.id,
                    leading: Icon(
                      entry.favorite ? Icons.star : Icons.auto_stories_outlined,
                    ),
                    title: Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${source.endpoint.host}${source.hasDiscovery ? '' : ' · 需搜索或输入链接'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () =>
                        Navigator.pop(context, (id: source.id as String?)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _DiscoveryBookCard extends StatelessWidget {
  const _DiscoveryBookCard({
    super.key,
    required this.book,
    required this.repository,
    required this.onTap,
  });
  final Book book;
  final BooksRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: BookCover(book: book, repository: repository),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            if (book.author.isNotEmpty)
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
