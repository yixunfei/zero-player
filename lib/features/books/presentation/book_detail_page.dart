import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/platform/file_transfer.dart';
import '../../supervision/domain/supervision_rules.dart';
import '../data/book_comic_export.dart';
import '../data/books_repository.dart';
import '../data/book_download_coordinator.dart';
import '../domain/book.dart';
import 'book_reader_page.dart';
import 'book_page_route.dart';
import 'rich_reader_page.dart';
import 'book_cover.dart';
import 'book_links.dart';
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
  final _directoryHeader = GlobalKey();
  static const _chapterExtent = 58.0;
  final _filter = TextEditingController();
  BookDownloadTask? _downloadTask;
  CancellationToken? _token;
  BooksRepository get _books => widget.services.books;
  bool get _audio => _book.kind == BookKind.audio;
  bool get _comic => _book.kind == BookKind.comic;
  bool get _local => _book.sourceId == 'local';

  @override
  void initState() {
    super.initState();
    _books.policy.addListener(_policyChanged);
    _downloadTask = widget.services.bookDownloads.active(_book);
    _downloadTask?.addListener(_downloadChanged);
    _saved.addAll(_downloadTask?.savedChapterIds ?? const {});
    _run(_load);
  }

  @override
  void dispose() {
    _token?.cancel();
    _downloadTask?.removeListener(_downloadChanged);
    _books.policy.removeListener(_policyChanged);
    _catalogScroll.dispose();
    _filter.dispose();
    super.dispose();
  }

  void _policyChanged() {
    _token?.cancel();
    if (mounted) setState(() {});
  }

  void _attachDownloadTask(BookDownloadTask? task) {
    if (identical(_downloadTask, task)) return;
    _downloadTask?.removeListener(_downloadChanged);
    _downloadTask = task;
    task?.addListener(_downloadChanged);
    if (task != null) _saved.addAll(task.savedChapterIds);
    if (mounted) setState(() {});
  }

  void _downloadChanged() {
    final task = _downloadTask;
    if (task == null || !mounted) return;
    if (task.status == BookDownloadStatus.running) {
      setState(() => _saved.addAll(task.savedChapterIds));
      return;
    }
    _attachDownloadTask(null);
    unawaited(_finishDownload(task));
  }

  Future<void> _finishDownload(BookDownloadTask task) async {
    try {
      final saved = task.book.kind == BookKind.audio
          ? await _books.audioFiles.saved(task.book)
          : task.book.kind == BookKind.comic
          ? await _books.store.savedImages(task.book)
          : await _books.store.savedText(task.book);
      final plan = BookDownloadPlan.fromJson(
        await _books.store.read('books_download:${task.book.id}'),
      );
      if (!mounted || _book.id != task.book.id) return;
      setState(() {
        _saved = saved;
        _plan = plan;
      });
    } on Exception {
      if (mounted && _book.id == task.book.id) {
        _toast('下载状态读取失败，请刷新目录');
      }
      return;
    }
    switch (task.status) {
      case BookDownloadStatus.completed:
        _toast('已完成 ${task.total - task.failures} 章，失败 ${task.failures} 章');
      case BookDownloadStatus.paused:
        _toast(task.error ?? '下载已暂停');
      case BookDownloadStatus.failed:
        _toast(task.error ?? '下载未完成');
      case BookDownloadStatus.running:
        break;
    }
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
    final plan = BookDownloadPlan.fromJson(
      await _books.store.read('books_download:${_book.id}'),
    );
    final details = _loadDetails(token);
    Object? catalogError;
    final chapters = await _books
        .chapters(_book, token, refresh: refresh)
        .onError((Exception error, _) {
          catalogError = error;
          return <BookChapter>[];
        });
    final saved = _audio
        ? await _books.audioFiles.saved(_book)
        : _comic
        ? await _books.store.savedImages(_book)
        : await _books.store.savedText(_book);
    if (!mounted || token.isCancelled) return;
    setState(() {
      _chapters = chapters.isEmpty ? existing?.chapters ?? [] : chapters;
      _saved = saved..addAll(_downloadTask?.savedChapterIds ?? const {});
      _last = existing?.last;
      _favorite = existing?.favorite ?? false;
      _following = existing?.following ?? false;
      _position = existing?.position ?? 0;
      _chapterUpdatedAt = existing?.chapterUpdatedAt;
      _plan = plan;
      _sourceUnavailable =
          !_local && (chapters.isEmpty || channel?.enabled != true);
    });
    _attachDownloadTask(widget.services.bookDownloads.active(_book));
    if (refresh && chapters.isNotEmpty && existing != null) {
      token.check();
      if (existing.following) {
        await _books.store.updateFollowedChapters(_book, chapters);
      } else {
        await _books.store.saveBook(_book, chapters: chapters);
      }
    }
    await details;
    if (catalogError case final Object error) throw error;
  }

  Future<void> _loadDetails(CancellationToken token) async {
    if (_local) return;
    try {
      final details = await _books.details(_book, token);
      if (mounted && !token.isCancelled) setState(() => _book = details);
    } on Exception {
      // Catalog access and saved progress can remain available independently.
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

  Future<void> _exportOfflineText() => _run((token) async {
    final buffer = StringBuffer('${_book.title}\n${_book.author}\n\n');
    final included = <(BookChapter, String)>[];
    var exported = 0;
    for (final chapter in _chapters) {
      token.check();
      if (!_saved.contains(chapter.id)) continue;
      _books.requireBook(_book, chapter);
      final body = await _books.store.text(_book, chapter);
      if (body == null || !_books.policy.textAllowed(body)) continue;
      buffer.write('${chapter.title}\n\n$body\n\n');
      included.add((chapter, body));
      exported++;
    }
    if (exported == 0) throw const FormatException('没有可导出的离线章节');
    final name = _book.title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
    void validate() {
      token.check();
      if (!_books.bookAllowed(_book)) throw const ContentBlocked();
      for (final (chapter, body) in included) {
        _books.requireBook(_book, chapter);
        if (!_books.policy.textAllowed(body)) throw const ContentBlocked();
      }
    }

    validate();
    await FileTransfer.saveText(
      '$name.txt',
      buffer.toString(),
      beforeWrite: validate,
    );
    if (mounted) _toast('已导出 $exported 章');
  });

  Future<void> _exportOfflineImages() => _run((token) async {
    final files = <ComicExportImage>[];
    final contents = <String>['${_book.title} · ${_book.author}'];
    var chapters = 0;
    for (final chapter in _chapters) {
      token.check();
      if (!_saved.contains(chapter.id)) continue;
      _books.requireBook(_book, chapter);
      final images = await _books.store.offlineImages(_book, chapter);
      if (images == null || images.isEmpty) continue;
      chapters++;
      final folder = chapters.toString().padLeft(4, '0');
      contents.add('$folder  ${chapter.title}');
      var index = 0;
      for (final image in images.entries) {
        token.check();
        final extension =
            image.key.pathSegments.lastOrNull
                ?.toLowerCase()
                .split('.')
                .lastOrNull ??
            '';
        final suffix =
            const {'png', 'jpg', 'jpeg', 'webp', 'gif'}.contains(extension)
            ? extension
            : 'img';
        files.add((
          path: '$folder/${(++index).toString().padLeft(4, '0')}.$suffix',
          bytes: image.value,
        ));
      }
    }
    if (chapters == 0) throw const FormatException('没有可导出的离线漫画');
    void validate() {
      token.check();
      if (!_books.bookAllowed(_book)) throw const ContentBlocked();
      for (final chapter in _chapters.where((c) => _saved.contains(c.id))) {
        _books.requireBook(_book, chapter);
      }
    }

    validate();
    final indexText = contents.join('\n');
    final zipBytes = await encodeComicArchive(files, indexText);
    validate();
    final name = _book.title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
    final directory = await (await getTemporaryDirectory()).createTemp(
      'zero-comic-',
    );
    try {
      final file = File('${directory.path}/$name.zip');
      await file.writeAsBytes(zipBytes, flush: true);
      await FileTransfer.saveFile(
        file,
        '$name.zip',
        'application/zip',
        beforeWrite: validate,
      );
      if (mounted) _toast('已导出 $chapters 章');
    } finally {
      await directory.delete(recursive: true);
    }
  });

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
      token.check();
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
    _attachDownloadTask(widget.services.bookDownloads.active(_book));
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
          onPressed: _busy || _downloadTask != null
              ? null
              : () => _download(plan),
          child: const Text('继续下载'),
        ),
      OutlinedButton(
        onPressed: _busy || _downloadTask != null ? null : _chooseDownload,
        child: const Text('离线下载'),
      ),
    ],
  );

  Future<void> _download(BookDownloadPlan plan, {bool keepPlan = true}) async {
    if (_busy || _downloadTask != null) return;
    final task = widget.services.bookDownloads.start(
      _book,
      _chapters,
      plan,
      keepPlan: keepPlan,
    );
    _attachDownloadTask(task);
    if (keepPlan) setState(() => _plan = plan);
  }

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
      _scrollCatalogTo(header + index * _chapterExtent);
    });
  }

  void _scrollCatalogTo(double offset) {
    if (!_catalogScroll.hasClients) return;
    final target = offset.clamp(0.0, _catalogScroll.position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _catalogScroll.jumpTo(target);
    } else {
      unawaited(
        _catalogScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void _showDirectory() {
    final header = _catalogHeader.currentContext?.size?.height;
    final toolbar = _directoryHeader.currentContext?.size?.height;
    if (header != null && toolbar != null) _scrollCatalogTo(header - toolbar);
  }

  Widget _directoryMenu(bool hasCurrent) => PopupMenuButton<String>(
    tooltip: '章节导航',
    icon: const Icon(Icons.format_list_bulleted),
    onSelected: (action) {
      switch (action) {
        case 'directory':
          _showDirectory();
        case 'current':
          _jumpToCurrent();
        case 'top':
          _scrollCatalogTo(0);
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'directory', child: Text('章节目录')),
      PopupMenuItem(
        value: 'current',
        enabled: hasCurrent,
        child: const Text('定位当前章节'),
      ),
      const PopupMenuItem(value: 'top', child: Text('目录回顶')),
    ],
  );

  Widget _workActions() => PopupMenuButton<String>(
    tooltip: '作品操作',
    enabled: !_busy,
    onSelected: (value) {
      switch (value) {
        case 'copyBook':
          copyBookLink(context, _book.uri);
        case 'copySource':
          final source = _channel?.source;
          if (source != null) copyBookLink(context, source.endpoint);
        case 'source':
          _changeSource();
        case 'refresh':
          _run((token) => _load(token, refresh: true));
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'copyBook', child: Text('复制书籍网页链接')),
      if (_channel != null)
        const PopupMenuItem(value: 'copySource', child: Text('复制渠道链接')),
      const PopupMenuItem(value: 'source', child: Text('换源')),
      const PopupMenuItem(value: 'refresh', child: Text('刷新目录')),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final last = _chapters.where((chapter) => chapter.id == _last).firstOrNull;
    final visible = _visibleChapters;
    return Scaffold(
      appBar: _appBar(last != null),
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
                      if (_busy || _downloadTask != null)
                        LinearProgressIndicator(
                          value:
                              _downloadTask != null && _downloadTask!.total > 0
                              ? _downloadTask!.finished / _downloadTask!.total
                              : null,
                        ),
                      _summary(last),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(child: Text(_error!)),
                              TextButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                        (token) => _load(token, refresh: true),
                                      ),
                                icon: const Icon(Icons.refresh),
                                label: const Text('重试加载'),
                              ),
                            ],
                          ),
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
                    itemExtent: _chapterExtent,
                    itemCount: visible.length,
                    itemBuilder: (_, index) => _chapter(visible[index]),
                  ),
              ],
            ),
    );
  }

  AppBar _appBar(bool hasLast) => AppBar(
    title: Text(_book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    actions: [
      if (_local && _books.bookAllowed(_book))
        IconButton(
          tooltip: '移除本地电子书',
          onPressed: _busy ? null : _removeLocal,
          icon: const Icon(Icons.delete_outline),
        ),
      if (_busy || _downloadTask != null)
        IconButton(
          tooltip: _downloadTask != null ? '暂停下载' : '取消当前操作',
          onPressed: () {
            if (_downloadTask case final task?) {
              task.pause();
            } else {
              _token?.cancel();
            }
          },
          icon: const Icon(Icons.stop_circle_outlined),
        ),
      if (_books.bookAllowed(_book) && _chapters.isNotEmpty)
        _directoryMenu(hasLast),
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
      if (!_local && _books.bookAllowed(_book)) _workActions(),
    ],
  );

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
    key: _directoryHeader,
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
        if (_book.rankLabel.isNotEmpty) Text('排行榜  第 ${_book.rankLabel} 名'),
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
            ..._storageActions(),
          ],
        ),
      ],
    ),
  );

  List<Widget> _storageActions() => [
    if (!_local && !_audio && _saved.isNotEmpty)
      OutlinedButton.icon(
        onPressed: _busy
            ? null
            : _comic
            ? _exportOfflineImages
            : _exportOfflineText,
        icon: const Icon(Icons.file_download_outlined),
        label: Text(_comic ? '导出离线漫画' : '导出离线章节'),
      ),
    if (!_local && !_audio)
      TextButton.icon(
        onPressed: _busy
            ? null
            : () => _run((_) async {
                await _books.store.clearReadingCache(_book);
                _toast('已清理本书阅读缓存；离线下载保留');
              }),
        icon: const Icon(Icons.cleaning_services_outlined),
        label: const Text('清理阅读缓存'),
      ),
  ];

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
                if (_book.wordCount.isNotEmpty) '字数 ${_book.wordCount}',
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
              onPressed: _busy || _downloadTask != null
                  ? null
                  : saved
                  ? () => _run((_) async {
                      if (_audio) {
                        await _books.audioFiles.remove(_book, chapter);
                      } else if (_comic) {
                        await _books.store.deleteImages(_book, chapter);
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
