import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../data/books_repository.dart';
import '../domain/book.dart';
import 'book_reader_page.dart';
import 'book_page_route.dart';
import 'rich_reader_page.dart';
import 'book_cover.dart';
import 'audiobook_player_page.dart';
import 'book_download_dialog.dart';
import 'book_source_favorite.dart';
import '../data/book_store.dart';

final class BookDetailPage extends StatefulWidget {
  const BookDetailPage({
    super.key,
    required this.services,
    required this.initial,
    this.onSearchAuthor,
    this.onSearchTitle,
    this.onSourceFavorite,
  });
  final AppServices services;
  final Book initial;
  final ValueChanged<String>? onSearchAuthor;
  final ValueChanged<Book>? onSearchTitle;
  final void Function(String id, bool favorite)? onSourceFavorite;

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

final class _BookDetailPageState extends State<BookDetailPage> {
  late Book _book = widget.initial;
  List<BookChapter> _chapters = [];
  Set<String> _saved = {};
  String? _last, _error;
  Map? _publication;
  String _chapterQuery = '';
  bool _favorite = false, _busy = false, _offline = false;
  bool _openingReader = false;
  bool _reverse = false, _expanded = false, _following = false;
  double _position = 0;
  DateTime? _chapterUpdatedAt;
  BookDownloadPlan? _plan;
  BookSourceEntry? _channel;
  bool _sourceUnavailable = false;
  final _catalogScroll = ScrollController();
  final _catalogHeader = GlobalKey();
  final _filter = TextEditingController();
  int _finished = 0, _total = 0;
  CancellationToken? _token;
  BooksRepository get _books => widget.services.books;
  bool get _audio => _book.kind == BookKind.audio;
  bool get _local => _book.sourceId == 'local';

  @override
  void initState() {
    super.initState();
    _books.policy.addListener(_policyChanged);
    _run(_load);
  }

  @override
  void dispose() {
    _token?.cancel();
    _books.policy.removeListener(_policyChanged);
    _catalogScroll.dispose();
    _filter.dispose();
    super.dispose();
  }

  void _policyChanged() {
    _token?.cancel();
    if (mounted) setState(() {});
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _run(Future<void> Function(CancellationToken) action) async {
    if (_busy) return;
    final token = _token = CancellationToken();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(token);
    } on FormatException catch (error) {
      if (mounted && !token.isCancelled) setState(() => _error = error.message);
    } on RemoteFailure catch (error) {
      if (mounted && !token.isCancelled) setState(() => _error = error.message);
    } catch (_) {
      if (mounted && !token.isCancelled) {
        setState(() => _error = '操作未完成，请检查来源或内容权限');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load(CancellationToken token, {bool refresh = false}) async {
    final channel = _local
        ? null
        : await _books.sourceEntry(_book.kind, _book.sourceId);
    if (!mounted || token.isCancelled) return;
    setState(() {
      _channel = channel;
      _sourceUnavailable = false;
    });
    final existing = await _books.store.entry(_book);
    final publication = await _books.store.read('publication_${_book.id}');
    if (mounted && publication is Map) {
      setState(() => _publication = publication);
    }
    final plan = BookDownloadPlan.fromJson(
      await _books.store.read('books_download:${_book.id}'),
    );
    List<BookChapter> chapters;
    try {
      chapters = await _books.chapters(_book, token, refresh: refresh);
    } on Exception {
      if (mounted && !token.isCancelled && !_local) {
        setState(() => _sourceUnavailable = true);
      }
      rethrow;
    }
    final saved = _audio
        ? await _books.audioFiles.saved(_book)
        : await _books.store.savedText(_book);
    if (!mounted || token.isCancelled) return;
    setState(() {
      _chapters = chapters.isEmpty && refresh
          ? existing?.chapters ?? []
          : chapters;
      _saved = saved;
      _last = existing?.last;
      _favorite = existing?.favorite ?? false;
      _following = existing?.following ?? false;
      _position = existing?.position ?? 0;
      _chapterUpdatedAt = existing?.chapterUpdatedAt;
      _plan = plan;
      _sourceUnavailable =
          !_local && (chapters.isEmpty || channel?.enabled != true);
    });
    if (refresh && chapters.isNotEmpty && existing != null) {
      if (existing.following) {
        await _books.store.updateFollowedChapters(_book, chapters);
      } else {
        await _books.store.saveBook(_book, chapters: chapters);
      }
    }
    try {
      final details = await _books.details(_book, token);
      if (mounted && !token.isCancelled) setState(() => _book = details);
    } on Exception {
      token.check();
    }
  }

  Future<void> _open(BookChapter chapter) async {
    if (_openingReader) return;
    _openingReader = true;
    final book = _book;
    try {
      _books.requireBook(book, chapter);
      if (_following) await _books.store.saveBook(book, clearUpdates: true);
      if (!mounted) return;
      final chapters = _chapters
          .where((c) => _books.policy.textAllowed(c.title))
          .toList();
      Widget? reader;
      if (_local) {
        for (final extension in ['epub', 'pdf']) {
          final file = _books.documentFile(book, extension);
          if (await file.exists()) {
            reader = RichReaderPage(
              repository: _books,
              book: book,
              file: file,
              initial: chapter,
              platform: widget.services.platform,
            );
            break;
          }
        }
      }
      if (!mounted) return;
      _books.requireBook(book, chapter);
      reader ??= _audio
          ? AudiobookPlayerPage(
              services: widget.services,
              book: book,
              chapters: chapters,
              initial: chapter,
            )
          : BookReaderPage(
              repository: _books,
              book: book,
              chapters: chapters,
              initial: chapter,
              platform: widget.services.platform,
            );
      final route = BookPageRoute<void>(builder: (_) => reader!);
      await Navigator.of(context, rootNavigator: true).push(route);
      await route.completed;
      if (mounted) await _run(_load);
    } on FormatException catch (error) {
      _toast(error.message);
    } on Exception {
      _toast('无法打开电子书，请重试');
    } finally {
      _openingReader = false;
    }
  }

  Future<void> _removeLocal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除本地电子书'),
        content: const Text('应用内副本、阅读进度及本书的书签笔记将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _run((_) async {
      await _books.removeLocalBook(_book);
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _changeSource() => _run((token) async {
    final editions = await _books.alternatives(_book, token);
    if (!mounted || token.isCancelled) return;
    if (editions.isEmpty) {
      _toast('当前启用的来源中没有同名同作者的版本');
      return;
    }
    final entries = await _books.sources(_book.kind);
    if (!mounted || token.isCancelled) return;
    final chosen = await showDialog<BookEdition>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('切换作品来源'),
        children: [
          for (final edition in editions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, edition),
              child: Text(
                '${entries.where((s) => s.source.id == edition.book.sourceId).firstOrNull?.source.name ?? edition.book.uri.host}'
                ' · ${edition.chapters.length} 章',
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted || token.isCancelled) return;
    final last = _chapters.where((chapter) => chapter.id == _last).firstOrNull;
    final next = last == null
        ? null
        : _books.matchingChapter(chosen.chapters, last);
    if (_favorite || next != null) {
      final previous = await _books.store.entry(_book);
      await _books.store.saveBook(
        chosen.book,
        chapters: chosen.chapters,
        favorite: _favorite ? true : null,
        last: next,
        position: next != null && !_audio ? previous?.position : null,
      );
    }
    if (!mounted || token.isCancelled) return;
    setState(() {
      _book = chosen.book;
      _chapters = [];
      _plan = null;
      _chapterQuery = '';
      _filter.clear();
    });
    await _load(token);
  });

  Future<void> _chooseDownload() async {
    final plan = await showBookDownloadDialog(context, _chapters.length);
    if (mounted && plan != null) await _download(plan);
  }

  Widget _downloadActions() => Wrap(
    spacing: 6,
    children: [
      if (_plan case final BookDownloadPlan plan)
        FilledButton.tonal(
          onPressed: _busy ? null : () => _download(plan),
          child: const Text('继续下载'),
        ),
      OutlinedButton(
        onPressed: _busy ? null : _chooseDownload,
        child: const Text('离线下载'),
      ),
    ],
  );

  Future<void> _download(BookDownloadPlan plan, {bool keepPlan = true}) =>
      _run((token) async {
        final storedIds = plan.chapterIds?.toSet();
        final range = storedIds != null
            ? _chapters
                  .where((chapter) => storedIds.contains(chapter.id))
                  .toList()
            : _chapters
                  .skip(plan.first - 1)
                  .take(plan.last - plan.first + 1)
                  .toList();
        final chapters = range
            .where((chapter) => !_saved.contains(chapter.id))
            .toList();
        final key = 'books_download:${_book.id}';
        if (chapters.isEmpty) {
          if (range.isEmpty) {
            _toast('目录中已找不到所选章节');
            return;
          }
          if (keepPlan) {
            await _books.store.write(key, null);
            if (mounted) setState(() => _plan = null);
          }
          _toast('当前可用章节已全部下载');
          return;
        }
        if (keepPlan) {
          final savedPlan = BookDownloadPlan(
            plan.first,
            plan.last,
            plan.fallback,
            chapterIds:
                plan.chapterIds ?? range.map((chapter) => chapter.id).toList(),
          );
          await _books.store.write(key, savedPlan.toJson());
          if (mounted) setState(() => _plan = savedPlan);
        }
        await _books.store.saveBook(_book, chapters: _chapters);
        if (!mounted || token.isCancelled) return;
        setState(() {
          _total = chapters.length;
          _finished = 0;
        });
        List<BookEdition>? alternatives;
        var failures = 0;
        try {
          for (final chapter in chapters) {
            token.check();
            try {
              try {
                await _books.download(_book, chapter, token);
              } on Exception {
                token.check();
                if (!plan.fallback) rethrow;
                alternatives ??= await _books.alternatives(_book, token);
                await _books.download(
                  _book,
                  chapter,
                  token,
                  alternatives: alternatives,
                  tryOriginal: false,
                );
              }
              if (mounted) setState(() => _saved.add(chapter.id));
            } on Exception {
              token.check();
              failures++;
            }
            if (mounted) setState(() => _finished++);
          }
          if (failures == 0 && keepPlan) {
            await _books.store.write(key, null);
            if (mounted) setState(() => _plan = null);
          }
          _toast('已完成 ${chapters.length - failures} 章，失败 $failures 章');
        } finally {
          if (mounted) setState(() => _total = 0);
        }
      });

  Future<void> _toggleFollowing() => _run((_) async {
    await _books.store.saveBook(
      _book,
      chapters: _chapters,
      following: !_following,
    );
    if (mounted) setState(() => _following = !_following);
  });

  List<BookChapter> get _visibleChapters {
    final chapters = _reverse ? _chapters.reversed : _chapters;
    return chapters
        .where(
          (c) =>
              _books.policy.textAllowed(c.title) &&
              (!_offline || _saved.contains(c.id)) &&
              c.title.toLowerCase().contains(_chapterQuery),
        )
        .toList();
  }

  void _jumpToCurrent() {
    if (_last == null) return;
    setState(() {
      _offline = false;
      _chapterQuery = '';
      _filter.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_catalogScroll.hasClients) return;
      final index = _visibleChapters.indexWhere(
        (chapter) => chapter.id == _last,
      );
      final header = _catalogHeader.currentContext?.size?.height;
      if (index < 0 || header == null) return;
      final position = _catalogScroll.position;
      final offset = (header + index * 58).clamp(0.0, position.maxScrollExtent);
      unawaited(
        _catalogScroll.animateTo(
          offset,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final last = _chapters.where((chapter) => chapter.id == _last).firstOrNull;
    final visible = _visibleChapters;
    return Scaffold(
      appBar: AppBar(
        title: Text(_book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_local && _books.bookAllowed(_book))
            IconButton(
              tooltip: '移除本地电子书',
              onPressed: _busy ? null : _removeLocal,
              icon: const Icon(Icons.delete_outline),
            ),
          if (_busy)
            IconButton(
              tooltip: '取消当前操作',
              onPressed: () => _token?.cancel(),
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          if (_books.bookAllowed(_book) && _channel != null)
            BookSourceFavorite(
              key: ValueKey(_channel!.source.id),
              repository: _books,
              entry: _channel!,
              onChanged: (value) {
                final entry = _channel;
                if (entry == null) return;
                setState(() => _channel = entry.withFavorite(value));
                widget.onSourceFavorite?.call(entry.source.id, value);
              },
            ),
          if (!_local && _books.bookAllowed(_book))
            PopupMenuButton<String>(
              tooltip: '作品操作',
              enabled: !_busy,
              onSelected: (value) => value == 'source'
                  ? _changeSource()
                  : _run((token) => _load(token, refresh: true)),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'source', child: Text('换源')),
                PopupMenuItem(value: 'refresh', child: Text('刷新目录')),
              ],
            ),
        ],
      ),
      body: !_books.bookAllowed(_book)
          ? const Center(child: Text('当前内容策略限制访问此作品'))
          : CustomScrollView(
              controller: _catalogScroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    key: _catalogHeader,
                    children: [
                      if (_busy)
                        LinearProgressIndicator(
                          value: _total > 0 ? _finished / _total : null,
                        ),
                      _summary(last),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_error!),
                        ),
                      if (_sourceUnavailable && !_busy) _sourceHelp(),
                      _directoryToolbar(),
                    ],
                  ),
                ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        _busy
                            ? '正在读取目录…'
                            : _offline
                            ? '暂无离线章节'
                            : '暂无匹配章节',
                      ),
                    ),
                  )
                else
                  SliverFixedExtentList.builder(
                    itemExtent: 58,
                    itemCount: visible.length,
                    itemBuilder: (_, index) => _chapter(visible[index]),
                  ),
              ],
            ),
    );
  }

  Widget _sourceHelp() => ListTile(
    leading: const Icon(Icons.link_off),
    title: const Text('当前渠道暂不可用'),
    subtitle: const Text('可以换源继续阅读，或重试目录。'),
    trailing: TextButton(
      onPressed: widget.onSearchTitle == null
          ? _changeSource
          : () => widget.onSearchTitle!(_book),
      child: const Text('查找其他渠道'),
    ),
  );

  Widget _directoryToolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: Text('目录 · ${_chapters.length} 章')),
            IconButton(
              tooltip: '定位当前章节',
              icon: const Icon(Icons.my_location),
              onPressed: _last == null ? null : _jumpToCurrent,
            ),
            TextButton.icon(
              icon: const Icon(Icons.sort),
              onPressed: () => setState(() => _reverse = !_reverse),
              label: Text(_reverse ? '倒序' : '正序'),
            ),
          ],
        ),
        if (_chapters.length > 10)
          TextField(
            controller: _filter,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '筛选章节',
              isDense: true,
            ),
            onChanged: (value) =>
                setState(() => _chapterQuery = value.trim().toLowerCase()),
          ),
      ],
    ),
  );

  Widget _summary(BookChapter? last) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bookHeading(),
        if (_publication != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '语种：${_publication!['language'] ?? ''}  版本：${_publication!['version'] ?? ''}\n译者／贡献者：${_publication!['translator'] ?? _publication!['author'] ?? ''}\n许可：${_publication!['license'] ?? '原书声明'}',
            ),
          ),
        if (_book.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _book.description,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? null : TextOverflow.ellipsis,
          ),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? '收起简介' : '展开简介'),
          ),
        ],
        if (_chapters.isNotEmpty || _book.latestChapter.isNotEmpty)
          Text(
            '最近章节  ${_book.latestChapter.isNotEmpty ? _book.latestChapter : _chapters.last.title}',
          ),
        if (last != null)
          Text(
            '当前进度  ${last.title}${_audio ? '' : ' · ${(_position.clamp(0, 1) * 100).round()}%'}',
          ),
        if (_book.updatedLabel.isNotEmpty) Text('更新时间  ${_book.updatedLabel}'),
        if (_book.updatedLabel.isEmpty && _chapterUpdatedAt != null)
          Text(
            '发现更新  ${MaterialLocalizations.of(context).formatShortDate(_chapterUpdatedAt!)}',
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_chapters.isNotEmpty)
              FilledButton.icon(
                onPressed: _busy ? null : () => _open(last ?? _chapters.first),
                icon: Icon(_audio ? Icons.play_arrow : Icons.menu_book),
                label: Text(
                  last == null
                      ? (_audio ? '开始听书' : '开始阅读')
                      : '继续${_audio ? '听书' : '阅读'}',
                ),
              ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run((_) async {
                      await _books.store.saveBook(
                        _book,
                        chapters: _local || _chapters.isEmpty
                            ? null
                            : _chapters,
                        favorite: !_favorite,
                      );
                      if (mounted) {
                        setState(() => _favorite = !_favorite);
                      }
                    }),
              icon: Icon(_favorite ? Icons.bookmark : Icons.bookmark_outline),
              label: Text(_favorite ? '已收藏' : '收藏'),
            ),
            FilterChip(
              label: const Text('仅离线'),
              selected: _offline,
              onSelected: (value) => setState(() => _offline = value),
            ),
            if (!_local)
              FilterChip(
                label: Text(_following ? '追更中' : '追更'),
                selected: _following,
                onSelected: _busy || _chapters.isEmpty
                    ? null
                    : (_) => _toggleFollowing(),
              ),
            if (!_local && _chapters.isNotEmpty) _downloadActions(),
          ],
        ),
      ],
    ),
  );

  Widget _bookHeading() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 64,
        height: 90,
        child: BookCover(book: _book, repository: _books),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_book.title, style: Theme.of(context).textTheme.titleLarge),
            if (_book.author.isNotEmpty)
              if (widget.onSearchAuthor != null)
                TextButton(
                  onPressed: () => widget.onSearchAuthor!(_book.author),
                  child: Text(_book.author),
                )
              else
                Text(_book.author),
            Text(
              [
                _book.category,
                _local ? '本地电子书' : _channel?.source.name ?? _book.uri.host,
                if (_chapters.isNotEmpty) '${_chapters.length} 章',
                if (_book.wordCount.isNotEmpty) '${_book.wordCount} 字数',
              ].where((x) => x.isNotEmpty).join(' · '),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _chapter(BookChapter chapter) {
    final saved = _saved.contains(chapter.id);
    return ListTile(
      title: Text(chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: chapter.id == _last,
      onTap: _busy ? null : () => _open(chapter),
      trailing: _local
          ? null
          : IconButton(
              tooltip: saved ? '删除离线章节' : '下载章节',
              icon: Icon(saved ? Icons.download_done : Icons.download_outlined),
              onPressed: _busy
                  ? null
                  : saved
                  ? () => _run((_) async {
                      if (_audio) {
                        await _books.audioFiles.remove(_book, chapter);
                      } else {
                        await _books.store.deleteText(_book, chapter);
                      }
                      if (mounted) setState(() => _saved.remove(chapter.id));
                    })
                  : () {
                      final index = _chapters.indexOf(chapter) + 1;
                      _download(
                        BookDownloadPlan(index, index, false),
                        keepPlan: false,
                      );
                    },
            ),
    );
  }
}
