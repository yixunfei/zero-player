import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/cancellation_token.dart';
import '../data/book_store.dart';
import '../data/books_repository.dart';
import '../domain/book.dart';
import '../domain/book_search.dart';
import 'book_cover.dart';
import 'book_links.dart';
import 'book_source_favorite.dart';

class BookSearchPage extends StatefulWidget {
  const BookSearchPage({
    super.key,
    required this.repository,
    required this.kind,
    required this.query,
    required this.onOpen,
    this.preferred,
    this.field = BookSearchField.all,
    this.sourceId,
    this.favoritesOnly = false,
    this.excludedSource,
    this.skipQidian = false,
    this.onSourceFavorite,
  });

  final BooksRepository repository;
  final BookKind kind;
  final String query;
  final Book? preferred;
  final BookSearchField field;
  final String? sourceId;
  final bool favoritesOnly;
  final String? excludedSource;
  final bool skipQidian;
  final void Function(String id, bool favorite)? onSourceFavorite;
  final Future<void> Function(Book) onOpen;

  @override
  State<BookSearchPage> createState() => _BookSearchPageState();
}

class _BookSearchPageState extends State<BookSearchPage> {
  final _results = <String, Book>{};
  final _sources = <String, BookSourceEntry>{};
  final _latencies = <String, int>{};
  final _failedSources = <String>{};
  late final _input = TextEditingController(text: widget.query);
  late String _query = widget.query;
  late BookSearchField _field = widget.field;
  late bool _scoped = widget.sourceId != null || widget.favoritesOnly;
  CancellationToken? _token;
  bool _busy = false;
  int _done = 0, _total = 0;
  bool _retrying = false;
  bool _cancelled = false;
  String? _error;
  Book? get _preferred => _query == widget.query && _field == widget.field
      ? widget.preferred
      : null;

  @override
  void initState() {
    super.initState();
    widget.repository.policy.addListener(_policyChanged);
    unawaited(_load());
  }

  void _policyChanged() => unawaited(_load());

  void _submit() {
    final query = _input.text.trim();
    if (query.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _query = query;
    unawaited(_load());
  }

  Future<void> _load({Set<String>? retry}) async {
    _token?.cancel();
    final token = _token = CancellationToken();
    final repository = widget.repository;
    final preferred = _preferred;
    setState(() {
      if (retry == null) {
        _results.clear();
        _sources.clear();
        _latencies.clear();
        _failedSources.clear();
        _done = _total = 0;
      }
      _busy = true;
      _retrying = retry != null;
      _cancelled = false;
      _error = null;
    });
    _updates.value++;
    try {
      await _loadSources(token, preferred, retrying: retry != null);
      final retried = <String>{};
      await repository.find(
        widget.kind,
        _query,
        token,
        field: _field,
        sourceId: _scoped ? widget.sourceId : null,
        sourceIds: retry,
        favorites: _scoped && widget.favoritesOnly,
        preferredSource: preferred?.sourceId,
        excludedSource: widget.excludedSource,
        skipQidian: widget.skipQidian,
        onProgress: (update) {
          if (update.sourceId case final String id) retried.add(id);
          _update(update, token, retrying: retry != null);
        },
      );
      if (mounted && !token.isCancelled && retry != null) {
        setState(() => _failedSources.removeAll(retry.difference(retried)));
      }
    } on FormatException catch (error) {
      if (mounted && !token.isCancelled) setState(() => _error = error.message);
    } on Exception {
      if (mounted && !token.isCancelled) setState(() => _error = '搜索未完成，请重试');
    } finally {
      if (mounted && identical(token, _token)) {
        setState(() => _busy = false);
        _updates.value++;
      }
    }
  }

  Future<void> _loadSources(
    CancellationToken token,
    Book? preferred, {
    required bool retrying,
  }) async {
    final repository = widget.repository;
    final sources = await repository.sources(widget.kind, enabledOnly: true);
    token.check();
    if (!mounted) return;
    setState(() {
      _sources
        ..clear()
        ..addEntries(sources.map((entry) => MapEntry(entry.source.id, entry)));
      if (retrying) {
        _results.removeWhere((_, book) => !_sources.containsKey(book.sourceId));
        _latencies.removeWhere((id, _) => !_sources.containsKey(id));
      }
      if (!retrying &&
          preferred != null &&
          _sources.containsKey(preferred.sourceId) &&
          repository.bookAllowed(preferred)) {
        _results[preferred.id] = preferred;
      }
    });
    _updates.value++;
  }

  void _update(
    BookSearchUpdate update,
    CancellationToken token, {
    required bool retrying,
  }) {
    if (!mounted || token.isCancelled) return;
    setState(() {
      if (!retrying) {
        _done = update.completed;
        _total = update.total;
      }
      final id = update.sourceId;
      if (id != null) {
        if (update.failed) {
          _failedSources.add(id);
        } else {
          _failedSources.remove(id);
        }
      }
      final latency = update.latencyMs;
      if (id != null && latency != null) _latencies[id] = latency;
      for (final book in update.books) {
        _results[book.id] = book;
      }
    });
    _updates.value++;
  }

  void _retryFailed() {
    if (_busy || _failedSources.isEmpty) return;
    unawaited(_load(retry: Set.of(_failedSources)));
  }

  void _cancelSearch() {
    _token?.cancel();
    setState(() {
      _busy = false;
      _cancelled = true;
    });
  }

  int _compareSources(Book a, Book b) {
    final preferred = _preferred?.id;
    if (a.id == preferred) return b.id == preferred ? 0 : -1;
    if (b.id == preferred) return 1;
    final favorite = (_sources[b.sourceId]?.favorite == true ? 1 : 0).compareTo(
      _sources[a.sourceId]?.favorite == true ? 1 : 0,
    );
    if (favorite != 0) return favorite;
    const unknownLatency = 1 << 30;
    final time = (_latencies[a.sourceId] ?? unknownLatency).compareTo(
      _latencies[b.sourceId] ?? unknownLatency,
    );
    return time != 0 ? time : a.id.compareTo(b.id);
  }

  List<List<Book>> _groups() {
    final groups = <String, List<Book>>{};
    final ranks = <String, int>{};
    final query = BookSearchQuery(_query, _field);
    for (final book in _results.values.where(widget.repository.bookAllowed)) {
      final title = book.title.trim();
      (groups[title] ??= []).add(book);
      final rank = query.rank(book) ?? 99;
      if (rank < (ranks[title] ?? 100)) ranks[title] = rank;
    }
    final titles = groups.keys.toList()
      ..sort((a, b) {
        final relevance = ranks[a]!.compareTo(ranks[b]!);
        if (relevance != 0) return relevance;
        return a.compareTo(b);
      });
    return titles.map((title) => groups[title]!).toList();
  }

  Future<void> _choose(List<Book> group) async {
    final title = group.first.title.trim();
    final book = await showDialog<Book>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: _updates,
        builder: (context, _) {
          final choices =
              _results.values
                  .where(
                    (book) =>
                        book.title.trim() == title &&
                        widget.repository.bookAllowed(book),
                  )
                  .toList()
                ..sort(_compareSources);
          return _sourceDialog(context, title, choices);
        },
      ),
    );
    if (!mounted || book == null || !widget.repository.bookAllowed(book)) {
      return;
    }
    await widget.onOpen(book);
    if (!mounted) return;
    final sources = await widget.repository.sources(
      widget.kind,
      enabledOnly: true,
    );
    if (mounted) {
      setState(
        () => _sources.addEntries(
          sources.map((entry) => MapEntry(entry.source.id, entry)),
        ),
      );
    }
  }

  final _updates = ValueNotifier<int>(0);

  Widget _sourceDialog(
    BuildContext context,
    String title,
    List<Book> choices,
  ) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 520,
      height: MediaQuery.sizeOf(context).height * .5,
      child: ListView.builder(
        itemCount: choices.length,
        itemBuilder: (_, index) {
          final book = choices[index];
          final entry = _sources[book.sourceId];
          final latency = _latencies[book.sourceId];
          return ListTile(
            title: Text(entry?.source.name ?? book.uri.host),
            subtitle: Text(
              [
                if (book.author.isNotEmpty) book.author,
                if (book.id == _preferred?.id) '当前渠道',
                latency == null ? (_busy ? '等待搜索' : '无搜索耗时') : '$latency ms',
              ].join(' · '),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BookLinkButton(label: '复制书籍网页链接', uri: book.uri),
                if (entry != null)
                  BookSourceFavorite(
                    key: ValueKey(book.id),
                    repository: widget.repository,
                    entry: entry,
                    onChanged: (value) {
                      setState(
                        () =>
                            _sources[book.sourceId] = entry.withFavorite(value),
                      );
                      _updates.value++;
                      widget.onSourceFavorite?.call(book.sourceId, value);
                    },
                  ),
              ],
            ),
            onTap: () => Navigator.pop(context, book),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );

  @override
  void dispose() {
    _token?.cancel();
    _input.dispose();
    _updates.dispose();
    widget.repository.policy.removeListener(_policyChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    return Scaffold(
      appBar: AppBar(title: const Text('聚合搜索')),
      body: Column(
        children: [
          _toolbar(),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          _searchStatus(groups.length),
          Expanded(
            child: groups.isEmpty
                ? Center(child: Text(_emptyMessage()))
                : ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (_, index) => _result(groups[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _searchStatus(int count) => ListTile(
    dense: true,
    title: Text(
      _error ??
          (_busy && _retrying
              ? '正在重试失败渠道…'
              : '${_cancelled ? '已取消 · ' : ''}$_done / $_total 个渠道 · $count 部作品'
                    '${_failedSources.isEmpty ? '' : ' · ${_failedSources.length} 个渠道失败'}'),
    ),
    trailing: !_busy && _failedSources.isNotEmpty
        ? TextButton(onPressed: _retryFailed, child: const Text('重试失败渠道'))
        : null,
  );

  String _emptyMessage() {
    if (_busy) return '正在搜索…';
    if (_cancelled) return '搜索已取消';
    if (_error != null) return '搜索未完成';
    if (_total == 0) return '没有可用于此次搜索的启用渠道';
    if (_failedSources.length == _total) return '本次搜索的渠道均请求失败';
    return '没有符合条件的作品';
  }

  Widget _result(List<Book> group) {
    group.sort(_compareSources);
    final book = group.first;
    final authors = group
        .map((book) => book.author)
        .where((name) => name.isNotEmpty)
        .toSet();
    return ListTile(
      key: ValueKey(book.title.trim()),
      leading: SizedBox(
        width: 38,
        height: 52,
        child: BookCover(book: book, repository: widget.repository),
      ),
      title: Text(book.title),
      subtitle: Text(
        [
          if (authors.isNotEmpty) authors.join(' / '),
          '${group.map((book) => book.sourceId).toSet().length} 个渠道',
          if (group.any((book) => book.id == _preferred?.id)) '含当前渠道',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _choose(group),
    );
  }

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submit(),
                maxLength: 2048,
                decoration: const InputDecoration(
                  hintText: '输入书名、作者或书籍链接',
                  counterText: '',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            IconButton(
              tooltip: _busy ? '取消搜索' : '搜索',
              icon: Icon(_busy ? Icons.stop : Icons.search),
              onPressed: _busy ? _cancelSearch : _submit,
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final (field, label) in const [
              (BookSearchField.all, '全部'),
              (BookSearchField.title, '书名'),
              (BookSearchField.author, '作者'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _field == field,
                onSelected: (_) {
                  if (_field == field) return;
                  _field = field;
                  _submit();
                },
              ),
            if (_scoped)
              InputChip(
                label: Text(
                  widget.favoritesOnly
                      ? '收藏渠道'
                      : _sources[widget.sourceId]?.source.name ?? '当前渠道',
                ),
                onDeleted: () {
                  _scoped = false;
                  _submit();
                },
              ),
          ],
        ),
      ],
    ),
  );
}
