import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../data/book_store.dart';
import '../domain/book.dart';
import 'book_detail_page.dart';
import 'book_sources_page.dart';

final class BooksPage extends StatefulWidget {
  const BooksPage({super.key, required this.services, required this.kind});
  final AppServices services;
  final BookKind kind;

  @override
  State<BooksPage> createState() => _BooksPageState();
}

final class _BooksPageState extends State<BooksPage> {
  final _search = TextEditingController();
  CancellationToken? _token;
  List<Book> _results = [];
  List<BookShelfEntry> _shelf = [];
  List<BookSourceEntry> _sources = [];
  bool _busy = false;
  int _tab = 0;
  int _failed = 0;
  String? _group;
  bool _favorites = false;
  String? _error;
  bool get _audio => widget.kind == BookKind.audio;
  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _services.contentPolicy.addListener(_policyChanged);
    unawaited(_reload());
  }

  void _policyChanged() {
    _token?.cancel();
    if (!mounted) return;
    setState(() {
      _results = [];
      _sources = [];
      _busy = false;
    });
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final sources = await _services.books.sources(widget.kind);
      final shelf = await _services.books.store.shelf();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        if (!_sources.any((s) => s.group == _group)) _group = null;
        _shelf = shelf
            .where(
              (entry) =>
                  entry.book.kind == widget.kind &&
                  _services.books.bookAllowed(entry.book),
            )
            .toList();
      });
      if (_tab == 0 && _services.books.kindAllowed(widget.kind)) await _find();
    } on Exception {
      if (mounted) setState(() => _error = '无法打开书库，请重试');
    }
  }

  Future<void> _find() async {
    _token?.cancel();
    final token = _token = CancellationToken();
    setState(() {
      _busy = true;
      _error = null;
      _results = [];
    });
    try {
      final result = await _services.books.find(
        widget.kind,
        _search.text.trim(),
        token,
        group: _group,
        favorites: _favorites,
      );
      if (!mounted || token.isCancelled) return;
      setState(() {
        _results = result.books;
        _failed = result.failed;
      });
    } on Exception {
      if (mounted && !token.isCancelled) {
        setState(() => _error = '搜索失败或受内容策略限制');
      }
    } finally {
      if (mounted && identical(_token, token)) setState(() => _busy = false);
    }
  }

  Future<void> _open(Book book) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailPage(services: _services, initial: book),
      ),
    );
    if (!mounted) return;
    final shelf = await _services.books.store.shelf();
    if (mounted) {
      setState(
        () => _shelf = shelf
            .where(
              (entry) =>
                  entry.book.kind == widget.kind &&
                  _services.books.bookAllowed(entry.book),
            )
            .toList(),
      );
    }
  }

  Future<void> _import() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: '电子书', extensions: ['txt', 'epub']),
        ],
      );
      if (file == null || !mounted) return;
      final book = await _services.books.importLocal(File(file.path));
      if (mounted) await _open(book);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法导入。请检查 TXT 或 EPUB 的格式、大小和内容权限。')),
        );
      }
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    _search.dispose();
    _services.contentPolicy.removeListener(_policyChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_services.books.kindAllowed(widget.kind)) {
      return const Center(child: Text('当前内容策略限制访问此模块'));
    }
    final groups =
        _sources.map((s) => s.group).where((s) => s.isNotEmpty).toSet().toList()
          ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 10,
            spacing: 10,
            children: [
              Text(_audio ? '听书' : '阅读', style: theme.textTheme.headlineMedium),
              Wrap(
                spacing: 8,
                children: [
                  if (!_audio)
                    OutlinedButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('导入电子书'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BookSourcesPage(
                            services: _services,
                            kind: widget.kind,
                          ),
                        ),
                      );
                      if (mounted) await _reload();
                    },
                    icon: const Icon(Icons.tune),
                    label: const Text('源管理'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('发现'),
                  icon: Icon(Icons.explore_outlined),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('书架'),
                  icon: Icon(Icons.collections_bookmark_outlined),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (value) {
                setState(() => _tab = value.first);
                if (_tab == 0 && _results.isEmpty && !_busy) unawaited(_find());
              },
            ),
          ),
        ),
        if (_tab == 0) _searchBar(groups),
        if (_tab == 0 && _busy) const LinearProgressIndicator(),
        if (_tab == 0 && !_busy && _failed > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('$_failed 个源请求失败'),
          ),
        Expanded(child: _tab == 0 ? _discovery() : _library()),
      ],
    );
  }

  Widget _searchBar(List<String> groups) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          maxLength: 80,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _find(),
          decoration: InputDecoration(
            hintText: '搜索书名或关键词',
            counterText: '',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: _busy ? '取消搜索' : '搜索',
              onPressed: _busy
                  ? () {
                      _token?.cancel();
                      setState(() => _busy = false);
                    }
                  : _find,
              icon: Icon(_busy ? Icons.close : Icons.arrow_forward),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            DropdownButton<String>(
              value: _group ?? '',
              items: [
                const DropdownMenuItem(value: '', child: Text('全部分组')),
                for (final group in groups)
                  DropdownMenuItem(value: group, child: Text(group)),
              ],
              onChanged: (value) {
                setState(() => _group = value == '' ? null : value);
                unawaited(_find());
              },
            ),
            FilterChip(
              label: const Text('仅收藏源'),
              selected: _favorites,
              onSelected: (value) {
                setState(() => _favorites = value);
                unawaited(_find());
              },
            ),
          ],
        ),
      ],
    ),
  );

  Widget _discovery() {
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _error ??
              (_busy
                  ? '正在加载作品…'
                  : _sources.any((s) => s.enabled)
                  ? '没有匹配作品'
                  : '请在源管理中启用一个渠道'),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final book = _results[index];
        final source = _sources
            .where((entry) => entry.source.id == book.sourceId)
            .firstOrNull;
        return _bookTile(book, [
          book.author,
          source?.source.name ?? '',
          book.description,
        ]);
      },
    );
  }

  Widget _library() {
    if (_shelf.isEmpty) {
      return const Center(child: Text('打开作品后可收藏，阅读与播放进度会保存在这里'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      itemCount: _shelf.length,
      itemBuilder: (context, index) {
        final entry = _shelf[index];
        final last = entry.chapters
            .where((c) => c.id == entry.last)
            .firstOrNull;
        return _bookTile(entry.book, [
          entry.favorite ? '已收藏' : '',
          entry.book.author,
          last?.title ?? '',
        ]);
      },
    );
  }

  Widget _bookTile(Book book, List<String> info) => ListTile(
    leading: CircleAvatar(
      child: Icon(_audio ? Icons.headphones : Icons.auto_stories_outlined),
    ),
    title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      info.where((value) => value.isNotEmpty).join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => _open(book),
  );
}
