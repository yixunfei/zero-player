import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/platform/platform_services.dart';
import '../data/books_repository.dart';
import '../domain/book.dart';
import 'reader_pagination.dart';
import 'reader_automation.dart';
import 'reader_style.dart';
import 'reader_system_ui.dart';

part 'reader_tools.dart';
part 'reader_session.dart';

final class BookReaderPage extends StatefulWidget {
  const BookReaderPage({
    super.key,
    required this.repository,
    required this.book,
    required this.chapters,
    required this.initial,
    this.platform,
  });
  final BooksRepository repository;
  final Book book;
  final List<BookChapter> chapters;
  final BookChapter initial;
  final PlatformServices? platform;

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

final class _BookReaderPageState extends State<BookReaderPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late BookChapter _chapter = widget.initial;
  late final _systemUi = ReaderSystemUi(widget.platform);
  GlobalKey<ReaderViewportState> _viewport = GlobalKey();
  final _paperFocus = FocusNode(debugLabel: '阅读正文');
  final _contentsFocus = FocusNode(debugLabel: '章节目录');
  final _progress = ValueNotifier<ReaderProgress>(readerProgress(0));
  CancellationToken? _token;
  Timer? _saveTimer, _clock;
  late final _automation = ReaderAutomation(this, _advanceAutomatically);
  bool _autoRunning = false;
  bool _preferencesLoaded = false;
  bool _configuring = false;
  ReaderPreferences _style = const ReaderPreferences();
  ReaderProgress? _retryPosition;
  TextRange? _highlight;
  String _sourceStatus = '', _selection = '', _text = '';
  String _chapterQuery = '', _findQuery = '';
  bool _reverse = false, _controls = false, _loading = true;
  String? _error;
  double? _seeking;

  BooksRepository get _books => widget.repository;
  int get _index => widget.chapters.indexOf(_chapter);
  bool get _ready => !_loading && _error == null && _text.isNotEmpty;

  void _changeAutomation(bool running) => setState(() {
    _autoRunning = running;
    if (running) _controls = false;
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _books.policy.addListener(_policyChanged);
    unawaited(_start());
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _style.status) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_preferencesLoaded && ModalRoute.of(context)?.isCurrent == true) {
        _systemUi.apply(_style.immersive);
      }
    } else {
      _stopAutomation();
      _savePosition();
    }
  }

  Future<void> _start() async {
    try {
      final data = await _books.store.read('books_reader_preferences');
      if (data is Map && mounted) {
        setState(() => _style = ReaderPreferences.fromJson(data));
      }
    } on Exception {
      // A damaged preference record can be replaced in the style panel.
    }
    if (mounted) {
      _preferencesLoaded = true;
      _systemUi.apply(_style.immersive);
    }
    if (mounted && _token == null) {
      await _open(widget.initial, resume: true);
      if (mounted && _style.autoEnabled) _startAutomation();
    }
  }

  void _policyChanged() {
    _stopAutomation();
    _token?.cancel();
    if (mounted) {
      unawaited(
        _open(
          _chapter,
          resume: true,
          location: _ready ? _progress.value : _retryPosition,
        ),
      );
    }
  }

  void _moved(ReaderProgress progress) {
    if (!_ready) return;
    if (_controls && progress.offset != _progress.value.offset) {
      setState(() => _controls = false);
    }
    _progress.value = progress;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 550), _savePosition);
  }

  void _savePosition() {
    if (!_ready) return;
    final progress = _progress.value;
    unawaited(
      _books.store
          .saveBook(
            widget.book,
            last: _chapter,
            position: progress.fraction,
            textOffset: progress.offset,
          )
          .onError((_, _) {}),
    );
  }

  Future<void> _open(
    BookChapter chapter, {
    bool resume = false,
    ReaderProgress? location,
  }) async {
    _saveTimer?.cancel();
    _savePosition();
    _token?.cancel();
    final token = _token = CancellationToken();
    _retryPosition = location;
    setState(() {
      _chapter = chapter;
      _viewport = GlobalKey();
      _loading = true;
      _error = null;
      _text = _selection = _sourceStatus = '';
      _controls = false;
      _highlight = null;
      _seeking = null;
    });
    _progress.value = readerProgress(0);
    try {
      final saved = resume && location == null
          ? await _books.store.entry(widget.book)
          : null;
      token.check();
      final result = await _books.readWithFallback(
        widget.book,
        chapter,
        token,
        automatic: _style.automatic,
      );
      if (!mounted || token.isCancelled) return;
      final restored =
          location ??
          (saved?.last == chapter.id
              ? readerProgress(
                  saved!.position.clamp(0.0, 1.0),
                  offset: saved.textOffset,
                )
              : readerProgress(0));
      _progress.value = restored;
      setState(() {
        _text = _chapterText(chapter.title, result.text);
        _sourceStatus = result.sourceBook.id == widget.book.id
            ? ''
            : '已换源 · ${result.sourceBook.uri.host}';
        _loading = false;
      });
      unawaited(
        _books.store
            .saveBook(
              widget.book,
              chapters: widget.book.sourceId == 'local'
                  ? null
                  : widget.chapters,
              last: chapter,
              position: restored.fraction,
              textOffset: restored.offset,
            )
            .onError((_, _) {}),
      );
    } on FormatException catch (error) {
      _fail(token, error.message);
    } on RemoteFailure catch (error) {
      _fail(token, error.message);
    } on Exception {
      _fail(token, '无法打开正文或内容受限');
    }
  }

  void _fail(CancellationToken token, String message) {
    if (mounted && !token.isCancelled) {
      _stopAutomation();
      setState(() {
        _loading = false;
        _error = message;
      });
    }
  }

  bool _canCross(int direction) {
    final index = _index + direction;
    return _ready &&
        index >= 0 &&
        index < widget.chapters.length &&
        _books.policy.textAllowed(widget.chapters[index].title);
  }

  void _cross(int direction, {bool lastPage = true}) {
    if (_canCross(direction)) {
      unawaited(
        _open(
          widget.chapters[_index + direction],
          location: readerProgress(direction < 0 && lastPage ? 1 : 0),
        ),
      );
    }
  }

  void _page(int direction) {
    _stopAutomation();
    if (_controls) {
      setState(() => _controls = false);
      _paperFocus.requestFocus();
    }
    if (_ready) _viewport.currentState?.turn(direction);
  }

  void _toggleControls() {
    _stopAutomation();
    setState(() => _controls = !_controls);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (_controls ? _contentsFocus : _paperFocus).requestFocus();
    });
  }

  void _showMatch(TextRange match) {
    setState(() {
      _highlight = match;
      _controls = false;
    });
    _viewport.currentState?.jumpToOffset(match.start);
    _paperFocus.requestFocus();
  }

  void _readerNotice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, _controls ? 110 : 54),
      ),
    );
  }

  KeyEventResult _readingKey(FocusNode node, KeyEvent event) {
    if (_controls || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      if (event is KeyDownEvent) _toggleControls();
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.space) {
      _page(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _page(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _settings() async {
    _configuring = true;
    await showReaderSettings(
      context,
      _style.copyWith(autoEnabled: _autoRunning),
      (settings) {
        if (!mounted) return;
        final previous = _style;
        if (previous.immersive != settings.immersive) {
          _systemUi.apply(settings.immersive);
        }
        setState(() => _style = settings);
        if (!settings.autoEnabled) {
          _stopAutomation();
        } else if (!_autoRunning ||
            previous.mode != settings.mode ||
            previous.autoSeconds != settings.autoSeconds) {
          _startAutomation();
        }
      },
    );
    _configuring = false;
    if (mounted) {
      await _books.store.write('books_reader_preferences', _style.toJson());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _automation.dispose();
    _systemUi.restore();
    _saveTimer?.cancel();
    _clock?.cancel();
    _savePosition();
    _token?.cancel();
    _books.policy.removeListener(_policyChanged);
    _paperFocus.dispose();
    _contentsFocus.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _style.paper.palette(Theme.of(context).colorScheme);
    final readerTheme = ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansSC',
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: palette.brightness,
        surface: palette.paper,
      ),
    );
    return Theme(
      data: readerTheme,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.pageDown): () => _page(1),
          const SingleActivator(LogicalKeyboardKey.pageUp): () => _page(-1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
              _skipChapter(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
              _skipChapter(1),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _showFind,
        },
        child: Scaffold(
          backgroundColor: palette.paper,
          body: _readerBody(palette),
        ),
      ),
    );
  }

  Widget _readerBody(ReaderPalette palette) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(
        child: ReaderPaperSurface(palette: palette, texture: _style.texture),
      ),
      SafeArea(
        top: !_style.immersive,
        bottom: !_style.immersive,
        child: Listener(
          onPointerDown: (_) => _stopAutomation(),
          onPointerSignal: (_) => _stopAutomation(),
          child: _content(palette),
        ),
      ),
      if (_controls || !_ready)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(bottom: false, child: _topBar(palette)),
        ),
      if (_ready)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            child: _controls ? _menu(palette) : _footer(palette),
          ),
        ),
    ],
  );

  void _skipChapter(int direction) {
    _stopAutomation();
    _cross(direction, lastPage: false);
  }

  Widget _content(ReaderPalette palette) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.ink),
              ),
              TextButton(
                onPressed: () =>
                    _open(_chapter, resume: true, location: _retryPosition),
                child: const Text('重试正文'),
              ),
            ],
          ),
        ),
      );
    }
    return Focus(
      focusNode: _paperFocus,
      autofocus: !_controls,
      onKeyEvent: _readingKey,
      child: ReaderTapZones(
        horizontal: _style.mode.horizontal,
        selectionActive: () => _selection.isNotEmpty,
        onTurn: _page,
        onMenu: _toggleControls,
        child: ReaderViewport(
          key: _viewport,
          text: _text,
          titleLength: _chapter.title.length,
          style: TextStyle(
            fontFamily: _style.family,
            fontSize: _style.fontSize,
            height: _style.lineHeight,
            color: palette.ink,
          ),
          palette: palette,
          mode: _style.mode,
          animate: _style.animate,
          texture: _style.texture,
          margin: _style.margin,
          initial: _progress.value,
          highlight: _highlight,
          onProgress: _moved,
          canCross: _canCross,
          onBoundary: _cross,
          onSelection: (selection) => _selection = selection,
          onAnnotate: _addAnnotation,
        ),
      ),
    );
  }

  Widget _topBar(ReaderPalette palette) => Material(
    color: palette.paper,
    elevation: 2,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Row(
          children: [
            BackButton(color: palette.ink),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                      ),
                    ),
                    if (_sourceStatus.isNotEmpty)
                      Text(
                        _sourceStatus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: palette.accent),
                      ),
                  ],
                ),
              ),
            ),
            if (_ready) ...[
              IconButton(
                tooltip: '书签与笔记',
                color: palette.ink,
                icon: const Icon(Icons.bookmarks_outlined),
                onPressed: _annotations,
              ),
              IconButton(
                tooltip: '添加书签或笔记',
                color: palette.ink,
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: _addAnnotation,
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _footer(ReaderPalette palette) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: ValueListenableBuilder<ReaderProgress>(
          valueListenable: _progress,
          builder: (context, progress, _) {
            final label = !_style.status || !_ready
                ? ''
                : _style.mode == ReaderTurnMode.scroll
                ? '${(progress.fraction * 100).round()}%'
                : '${progress.page} / ${progress.pages} 页';
            return Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.ink.withValues(alpha: .76),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _autoRunning ? '停止自动阅读' : '阅读菜单',
                  iconSize: 20,
                  color: palette.ink,
                  onPressed: !_ready
                      ? null
                      : _autoRunning
                      ? _stopAutomation
                      : _toggleControls,
                  icon: Icon(
                    _autoRunning
                        ? Icons.pause_circle_outline
                        : Icons.more_horiz,
                  ),
                ),
                Expanded(
                  child: Text(
                    _style.status
                        ? MaterialLocalizations.of(context).formatTimeOfDay(
                            TimeOfDay.now(),
                            alwaysUse24HourFormat: true,
                          )
                        : '',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.ink.withValues(alpha: .76),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _menu(ReaderPalette palette) => Material(
    color: palette.paper,
    elevation: 4,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<ReaderProgress>(
              valueListenable: _progress,
              builder: (context, progress, _) {
                final value = _seeking ?? progress.fraction;
                return Row(
                  children: [
                    const SizedBox(width: 16),
                    Text(
                      '${_index + 1}/${widget.chapters.length} 章',
                      style: TextStyle(color: palette.ink, fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: value,
                        label: '${(value * 100).round()}%',
                        activeColor: palette.accent,
                        onChanged: (value) => setState(() => _seeking = value),
                        onChangeEnd: (value) {
                          setState(() => _seeking = null);
                          _viewport.currentState?.jump(value);
                        },
                      ),
                    ),
                    Text(
                      '${(value * 100).round()}%',
                      style: TextStyle(color: palette.ink, fontSize: 12),
                    ),
                    const SizedBox(width: 16),
                  ],
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: '上一页',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _page(-1),
                ),
                IconButton(
                  focusNode: _contentsFocus,
                  tooltip: '章节目录',
                  icon: const Icon(Icons.format_list_bulleted),
                  onPressed: _showChapters,
                ),
                IconButton(
                  tooltip: '章内查找',
                  icon: const Icon(Icons.search),
                  onPressed: _showFind,
                ),
                IconButton(
                  tooltip: '阅读样式',
                  icon: const Icon(Icons.text_fields),
                  onPressed: _settings,
                ),
                IconButton(
                  tooltip: '下一页',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _page(1),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String _chapterText(String title, String body) {
  final newline = body.indexOf('\n');
  final first = newline == -1 ? body : body.substring(0, newline);
  if (first.trim() != title.trim()) return '$title\n\n$body';
  if (newline == -1) return title;
  final rest = body
      .substring(newline + 1)
      .replaceFirst(RegExp(r'^(?:[ \t]*\r?\n)+'), '');
  return rest.isEmpty ? title : '$title\n\n$rest';
}
