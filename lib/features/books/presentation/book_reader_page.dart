import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../data/books_repository.dart';
import '../domain/book.dart';

enum _Paper { system, warm, dark }

final class BookReaderPage extends StatefulWidget {
  const BookReaderPage({
    super.key,
    required this.repository,
    required this.book,
    required this.chapters,
    required this.initial,
  });
  final BooksRepository repository;
  final Book book;
  final List<BookChapter> chapters;
  final BookChapter initial;

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

final class _BookReaderPageState extends State<BookReaderPage> {
  late BookChapter _chapter = widget.initial;
  final _scroll = ScrollController();
  final _progress = ValueNotifier<double>(0);
  CancellationToken? _token;
  Timer? _saveTimer;
  List<String> _paragraphs = [];
  String? _error;
  bool _loading = true;
  double _fontSize = 21, _lineHeight = 1.8;
  _Paper _paper = _Paper.system;
  BooksRepository get _books => widget.repository;
  int get _index => widget.chapters.indexOf(_chapter);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_moved);
    _books.policy.addListener(_policyChanged);
    unawaited(_open(widget.initial, resume: true));
    unawaited(_preferences());
  }

  Future<void> _preferences() async {
    final data = await _books.store.read('books_reader_preferences');
    if (data is Map && mounted) {
      setState(() {
        _fontSize = ((data['font'] as num?)?.toDouble() ?? 21).clamp(14, 34);
        _lineHeight = ((data['line'] as num?)?.toDouble() ?? 1.8).clamp(
          1.3,
          2.3,
        );
        _paper =
            _Paper.values.where((p) => p.name == data['paper']).firstOrNull ??
            _Paper.system;
      });
    }
  }

  void _policyChanged() {
    _token?.cancel();
    if (mounted) unawaited(_open(_chapter, resume: true));
  }

  void _moved() {
    if (_loading || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _progress.value = max <= 0 ? 0 : (_scroll.offset / max).clamp(0, 1);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 650), _savePosition);
  }

  void _savePosition() {
    if (_paragraphs.isEmpty || _loading) return;
    unawaited(
      _books.store
          .saveBook(widget.book, last: _chapter, position: _progress.value)
          .onError((_, _) {}),
    );
  }

  Future<void> _open(BookChapter chapter, {bool resume = false}) async {
    _saveTimer?.cancel();
    _savePosition();
    _token?.cancel();
    final token = _token = CancellationToken();
    setState(() {
      _chapter = chapter;
      _loading = true;
      _error = null;
      _paragraphs = [];
    });
    _progress.value = 0;
    try {
      final old = await _books.store.entry(widget.book);
      final body = await _books.readText(widget.book, chapter, token);
      final offset = resume && old?.last == chapter.id
          ? old!.position.clamp(0.0, 1.0)
          : 0.0;
      if (!mounted || token.isCancelled) return;
      setState(() {
        _paragraphs = body
            .split(RegExp(r'\n+'))
            .where((p) => p.trim().isNotEmpty)
            .expand((p) sync* {
              for (var i = 0; i < p.length; i += 1600) {
                yield p.substring(i, (i + 1600).clamp(0, p.length));
              }
            })
            .toList();
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(token, _token) && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent * offset);
        }
      });
      await _books.store.saveBook(
        widget.book,
        chapters: widget.chapters,
        last: chapter,
        position: offset,
      );
    } on FormatException catch (error) {
      if (mounted && !token.isCancelled) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    } on RemoteFailure catch (error) {
      if (mounted && !token.isCancelled) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted && !token.isCancelled) {
        setState(() {
          _loading = false;
          _error = '无法打开正文或内容受限';
        });
      }
    }
  }

  void _step(int direction) {
    final target = _index + direction;
    if (target >= 0 && target < widget.chapters.length) {
      unawaited(_open(widget.chapters[target]));
    }
  }

  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    unawaited(
      _scroll.animateTo(
        (_scroll.offset + direction * position.viewportDimension * .87).clamp(
          0,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
      ),
    );
  }

  Future<void> _showChapters() async {
    final chapters = widget.chapters
        .where((chapter) => _books.policy.textAllowed(chapter.title))
        .toList();
    final selected = await showModalBottomSheet<BookChapter>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          children: [
            const ListTile(title: Text('章节目录')),
            Expanded(
              child: ListView.builder(
                itemCount: chapters.length,
                itemBuilder: (context, index) {
                  final chapter = chapters[index];
                  return ListTile(
                    selected: chapter == _chapter,
                    title: Text(
                      chapter.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(context, chapter),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted && selected != null && selected != _chapter) {
      await _open(selected);
    }
  }

  Future<void> _settings() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('阅读样式'),
                Slider(
                  value: _fontSize,
                  min: 14,
                  max: 34,
                  divisions: 20,
                  label: '字号 ${_fontSize.round()}',
                  onChanged: (value) {
                    setState(() => _fontSize = value);
                    update(() {});
                  },
                ),
                Slider(
                  value: _lineHeight,
                  min: 1.3,
                  max: 2.3,
                  divisions: 10,
                  label: '行距 ${_lineHeight.toStringAsFixed(1)}',
                  onChanged: (value) {
                    setState(() => _lineHeight = value);
                    update(() {});
                  },
                ),
                SegmentedButton<_Paper>(
                  segments: const [
                    ButtonSegment(value: _Paper.system, label: Text('跟随系统')),
                    ButtonSegment(value: _Paper.warm, label: Text('暖纸')),
                    ButtonSegment(value: _Paper.dark, label: Text('夜间')),
                  ],
                  selected: {_paper},
                  onSelectionChanged: (value) {
                    setState(() => _paper = value.first);
                    update(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      await _books.store.write('books_reader_preferences', {
        'font': _fontSize,
        'line': _lineHeight,
        'paper': _paper.name,
      });
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition();
    _token?.cancel();
    _books.policy.removeListener(_policyChanged);
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = switch (_paper) {
      _Paper.system => (theme.colorScheme.surface, theme.colorScheme.onSurface),
      _Paper.warm => (const Color(0xfff6eddb), const Color(0xff352c20)),
      _Paper.dark => (const Color(0xff171a1e), const Color(0xffe6dfd3)),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _page(1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _page(-1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            _step(1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: background,
          appBar: AppBar(
            backgroundColor: background,
            foregroundColor: foreground,
            title: Text(
              _chapter.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: '章节目录',
                onPressed: _showChapters,
                icon: const Icon(Icons.list),
              ),
              IconButton(
                tooltip: '阅读样式',
                onPressed: _settings,
                icon: const Icon(Icons.text_fields),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Text(_error!, style: TextStyle(color: foreground)),
                )
              : _body(foreground),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: _index > 0 ? () => _step(-1) : null,
                  style: TextButton.styleFrom(foregroundColor: foreground),
                  child: const Text('上一章'),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  builder: (_, value, _) => Text(
                    '${_index + 1}/${widget.chapters.length} · ${(value * 100).round()}%',
                    style: TextStyle(color: foreground),
                  ),
                ),
                TextButton(
                  onPressed: _index < widget.chapters.length - 1
                      ? () => _step(1)
                      : null,
                  style: TextButton.styleFrom(foregroundColor: foreground),
                  child: const Text('下一章'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(Color foreground) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Scrollbar(
        controller: _scroll,
        child: SelectionArea(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
            itemCount: _paragraphs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    _chapter.title,
                    style: TextStyle(
                      fontFamily: 'NotoSerifSC',
                      fontSize: _fontSize + 7,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _paragraphs[index - 1],
                  style: TextStyle(
                    fontFamily: 'NotoSerifSC',
                    fontSize: _fontSize,
                    height: _lineHeight,
                    color: foreground,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
