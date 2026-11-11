import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../data/books_repository.dart';
import '../domain/book.dart';
import 'book_reader_page.dart';
import 'audiobook_player_page.dart';

final class BookDetailPage extends StatefulWidget {
  const BookDetailPage({
    super.key,
    required this.services,
    required this.initial,
  });
  final AppServices services;
  final Book initial;

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

final class _BookDetailPageState extends State<BookDetailPage> {
  late Book _book = widget.initial;
  List<BookChapter> _chapters = [];
  Set<String> _saved = {};
  String? _last, _error;
  String _chapterQuery = '';
  bool _favorite = false, _busy = false, _offline = false, _select = false;
  int _finished = 0, _total = 0;
  final _selection = <String>{};
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
    final existing = await _books.store.entry(_book);
    final chapters = await _books.chapters(_book, token, refresh: refresh);
    final saved = _audio
        ? await _books.audioFiles.saved(_book)
        : await _books.store.savedText(_book);
    if (!mounted || token.isCancelled) return;
    setState(() {
      _chapters = chapters;
      _saved = saved;
      _last = existing?.last;
      _favorite = existing?.favorite ?? false;
    });
  }

  Future<void> _open(BookChapter chapter) async {
    final chapters = _chapters
        .where((c) => _books.policy.textAllowed(c.title))
        .toList();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _audio
            ? AudiobookPlayerPage(
                services: widget.services,
                book: _book,
                chapters: chapters,
                initial: chapter,
              )
            : BookReaderPage(
                repository: _books,
                book: _book,
                chapters: chapters,
                initial: chapter,
              ),
      ),
    );
    if (mounted) await _run(_load);
  }

  Future<void> _removeLocal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除本地电子书'),
        content: const Text('应用内副本和阅读进度将被删除。'),
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
      await _books.store.removeLocal(_book);
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
      _chapterQuery = '';
      _selection.clear();
    });
    await _load(token);
  });

  Future<void> _download(List<BookChapter> chapters) => _run((token) async {
    setState(() {
      _total = chapters.length;
      _finished = 0;
    });
    var failures = 0;
    try {
      final alternatives = _local
          ? <BookEdition>[]
          : await _books.alternatives(_book, token);
      await _books.store.saveBook(_book, chapters: _chapters);
      for (final chapter in chapters) {
        token.check();
        try {
          await _books.download(
            _book,
            chapter,
            token,
            alternatives: alternatives,
          );
          if (mounted) setState(() => _saved.add(chapter.id));
        } on Exception {
          token.check();
          failures++;
        }
        if (mounted) setState(() => _finished++);
      }
      _toast('已完成 ${chapters.length - failures} 章，失败 $failures 章');
    } finally {
      if (mounted) {
        setState(() {
          _total = 0;
          _select = false;
          _selection.clear();
        });
      }
    }
  });

  @override
  Widget build(BuildContext context) {
    final last = _chapters.where((chapter) => chapter.id == _last).firstOrNull;
    final visible = _chapters
        .where(
          (c) =>
              _books.policy.textAllowed(c.title) &&
              (!_offline || _saved.contains(c.id)) &&
              c.title.toLowerCase().contains(_chapterQuery),
        )
        .toList();
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy)
                  LinearProgressIndicator(
                    value: _total > 0 ? _finished / _total : null,
                  ),
                _summary(last, visible),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!),
                  ),
                if (_chapters.length > 10)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                    child: TextField(
                      key: ValueKey(_book.id),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '筛选章节',
                        isDense: true,
                      ),
                      onChanged: (value) => setState(() {
                        _chapterQuery = value.trim().toLowerCase();
                        _selection.clear();
                      }),
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            _busy
                                ? '正在读取目录…'
                                : _offline
                                ? '暂无离线章节'
                                : '暂无可用章节',
                          ),
                        )
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (_, index) => _chapter(visible[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _summary(BookChapter? last, List<BookChapter> visible) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            _book.author,
            _local ? '本地电子书' : _book.uri.host,
            '${_chapters.length} 章',
          ].where((x) => x.isNotEmpty).join(' · '),
        ),
        if (_book.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _book.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
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
                        chapters: _chapters.isEmpty ? null : _chapters,
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
              onSelected: (value) => setState(() {
                _offline = value;
                _selection.clear();
              }),
            ),
            if (!_local && visible.isNotEmpty)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _select = !_select;
                        _selection.clear();
                      }),
                child: Text(_select ? '取消选章' : '批量下载'),
              ),
            if (_select)
              FilledButton(
                onPressed: _busy || _selection.isEmpty
                    ? null
                    : () => _download(
                        visible
                            .where((c) => _selection.contains(c.id))
                            .toList(),
                      ),
                child: Text('下载 ${_selection.length} 章'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _chapter(BookChapter chapter) {
    final saved = _saved.contains(chapter.id);
    if (_select) {
      return CheckboxListTile(
        title: Text(chapter.title),
        value: _selection.contains(chapter.id),
        onChanged: _busy || saved
            ? null
            : (value) => setState(() {
                if (value == true) {
                  if (_selection.length < 80) {
                    _selection.add(chapter.id);
                  } else {
                    _toast('每批最多下载 80 章');
                  }
                } else {
                  _selection.remove(chapter.id);
                }
              }),
      );
    }
    return ListTile(
      title: Text(chapter.title),
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
                  : () => _download([chapter]),
            ),
    );
  }
}
