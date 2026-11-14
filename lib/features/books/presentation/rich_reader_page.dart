import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../core/platform/platform_services.dart';
import '../data/local_book.dart';
import '../data/books_repository.dart';
import '../data/rich_book.dart';
import '../domain/book.dart';
import 'reader_style.dart';
import 'reader_automation.dart';
import 'reader_pagination.dart' show ReaderTapZones;
import 'reader_system_ui.dart';
import 'vertical_book_text.dart';
import 'package:fwfh_svg/fwfh_svg.dart';

class RichReaderPage extends StatefulWidget {
  const RichReaderPage({
    super.key,
    required this.repository,
    required this.book,
    required this.file,
    this.initial,
    this.platform,
  });
  final BooksRepository repository;
  final Book book;
  final File file;
  final BookChapter? initial;
  final PlatformServices? platform;
  @override
  State<RichReaderPage> createState() => _RichReaderState();
}

class _RichReaderState extends State<RichReaderPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  GlobalKey<VerticalBookTextState> _vertical = GlobalKey();
  bool _horizontal = false;
  bool _validated = false;
  final _pdf = PdfViewerController();
  late final _systemUi = ReaderSystemUi(widget.platform);
  PdfTextSearcher? _searcher;
  final _searchInput = TextEditingController();
  final _scroll = ScrollController(keepScrollOffset: false);
  List<RichSection>? _sections;
  List<BookChapter> _chapters = [];
  List<PdfOutlineNode> _outline = [];
  ReaderPreferences _style = const ReaderPreferences();
  int _index = 0;
  String? _error;
  String _query = '';
  String _selection = '';
  bool _controls = false, _auto = false;
  bool _configuring = false;
  Timer? _saveTimer;
  late final _automation = ReaderAutomation(this, _advanceAutomatically);
  double? _resumeOffset;
  double _lastScrollOffset = 0, _scrollFraction = 0;
  bool _restoringScroll = false;
  int _verticalPage = 0;
  bool get _isPdf => widget.file.path.toLowerCase().endsWith('.pdf');
  bool get _ready =>
      _validated && _error == null && (!_isPdf || _searcher != null);
  String get _positionKey => 'rich_position_${widget.book.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.repository.policy.addListener(_onPolicyChanged);
    _scroll.addListener(_scrolled);
    _load();
  }

  bool get _continuous =>
      !_isPdf &&
      (_horizontal || _sections?[_index].vertical == false) &&
      _style.mode == ReaderTurnMode.scroll;

  void _advanceAutomatically(double? seconds) {
    if (!_ready ||
        _controls ||
        (!_configuring && ModalRoute.of(context)?.isCurrent != true)) {
      return;
    }
    if (seconds == null || !_continuous) {
      if (seconds == null) _next(1);
      return;
    }
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - .01) {
      position.jumpTo(
        (position.pixels + _style.scrollSpeed * seconds).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
    } else {
      _crossSection(1);
    }
  }

  void _startAutomation() {
    if (!_ready || !_style.autoEnabled) return;
    _hideControls();
    if (!_auto) setState(() => _auto = true);
    _automation.start(scroll: _continuous, interval: _style.autoSeconds);
  }

  void _onPolicyChanged() {
    _stop();
    _saveTimer?.cancel();
    _searcher?.resetTextSearch();
    _searchInput.clear();
    setState(() {
      _auto = false;
      _controls = false;
      _query = '';
      _error = '内容策略已变更，请退出后重新打开';
    });
  }

  Future<void> _load() async {
    try {
      final repository = widget.repository;
      final data = await repository.store.read('books_reader_preferences');
      final stored = await repository.store.read(_positionKey);
      final saved = await repository.store.entry(widget.book);
      final chapters = saved?.chapters ?? const <BookChapter>[];
      if (chapters.isEmpty) throw const FormatException('电子书目录为空');
      final sections = _isPdf
          ? null
          : await readRichEpubOffThread(await readLocalBookBytes(widget.file));
      if (!mounted || _error != null) return;
      if (sections != null && sections.length != chapters.length) {
        throw const FormatException('EPUB 文件与已导入目录不一致');
      }
      if (!await _contentAllowed(chapters, sections)) {
        if (mounted && _error == null) {
          setState(() => _error = '当前内容策略限制访问此书');
        }
        return;
      }
      if (!mounted || _error != null) return;
      final storedIndex = stored is Map ? stored['index'] : stored;
      final selected = chapters.indexWhere(
        (chapter) => chapter.id == widget.initial?.id,
      );
      final index =
          (selected >= 0
                  ? selected
                  : storedIndex is int
                  ? storedIndex
                  : chapters.indexWhere((chapter) => chapter.id == saved?.last))
              .clamp(0, chapters.length - 1);
      setState(() {
        _validated = true;
        _chapters = chapters;
        if (data is Map) _style = ReaderPreferences.fromJson(data);
        _sections = sections;
        _index = index;
        if (stored is Map) {
          _horizontal = stored['horizontal'] == true;
          if (storedIndex == index) {
            final verticalPage = stored['verticalPage'];
            final offset = stored['offset'];
            if (verticalPage is int) {
              _verticalPage = verticalPage.clamp(0, 100000);
            }
            if (offset is num) {
              _resumeOffset = offset.toDouble().clamp(0, 10000000);
            }
            if (saved?.last == chapters[index].id) {
              _scrollFraction = saved!.position.clamp(0.0, 1.0);
            }
          }
        }
      });
      _save();
      _systemUi.apply(_style.immersive);
      if (!_isPdf && _style.autoEnabled) _startAutomation();
    } on Exception {
      if (mounted && _error == null) {
        setState(() => _error = '无法打开电子书，文件可能损坏或格式不受支持');
      }
    }
  }

  Future<bool> _contentAllowed(
    List<BookChapter> chapters,
    List<RichSection>? sections,
  ) async {
    final repository = widget.repository;
    if (!repository.bookAllowed(widget.book)) return false;
    for (final (index, chapter) in chapters.indexed) {
      if (!mounted || _error != null) return false;
      final cached = await repository.store.text(widget.book, chapter);
      if (cached == null ||
          !repository.policy.textAllowed(chapter.title) ||
          !repository.policy.textAllowed(cached)) {
        return false;
      }
      if (sections != null &&
          (!repository.policy.textAllowed(sections[index].title) ||
              !repository.policy.textAllowed(sections[index].text))) {
        return false;
      }
    }
    return repository.bookAllowed(widget.book);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_validated && ModalRoute.of(context)?.isCurrent == true) {
        _systemUi.apply(_style.immersive);
      }
    } else {
      _stop();
      _save();
    }
  }

  void _stop() {
    _automation.stop();
    if (_auto) setState(() => _auto = false);
  }

  void _scrolled() {
    if (!_ready ||
        !_scroll.hasClients ||
        !_scroll.position.hasContentDimensions) {
      return;
    }
    final position = _scroll.position;
    _lastScrollOffset = position.pixels.clamp(0.0, position.maxScrollExtent);
    _scrollFraction = position.maxScrollExtent > 0
        ? _lastScrollOffset / position.maxScrollExtent
        : 0;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 550), _save);
  }

  void _save() {
    if (!_ready || _index >= _chapters.length) return;
    unawaited(
      widget.repository.store
          .saveRichPosition(
            widget.book,
            _chapters[_index],
            index: _index,
            horizontal: _horizontal,
            verticalPage: _verticalPage,
            offset: _resumeOffset ?? _lastScrollOffset,
            fraction: _scrollFraction,
          )
          .onError((_, _) {}),
    );
  }

  void _hideControls() {
    if (!_controls) return;
    if (_query.isNotEmpty) FocusManager.instance.primaryFocus?.unfocus();
    _searcher?.resetTextSearch();
    _searchInput.clear();
    setState(() {
      _controls = false;
      _query = '';
    });
  }

  void _toggleControls() {
    _stop();
    if (_controls) {
      _hideControls();
    } else {
      _selection = '';
      setState(() => _controls = true);
    }
  }

  void _next(int direction) {
    if (!_ready) return;
    final wasShowingResults = !_isPdf && _query.isNotEmpty;
    _hideControls();
    if (wasShowingResults) return;
    if (_isPdf) {
      final page = (_pdf.pageNumber ?? 1) + direction;
      if (page < 1 || page > _chapters.length) {
        _stop();
        return;
      }
      _pdf.goToPage(pageNumber: page);
    } else if (_vertical.currentState case final viewport?) {
      viewport.turn(direction);
    } else if (_scroll.hasClients &&
        (direction > 0
            ? _scroll.offset < _scroll.position.maxScrollExtent - 1
            : _scroll.offset > 1)) {
      _scroll.animateTo(
        (_scroll.offset + direction * _scroll.position.viewportDimension * .9)
            .clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } else {
      _crossSection(direction);
    }
  }

  void _crossSection(int direction) {
    final next = _index + direction;
    if (next < 0 || next >= _sections!.length) {
      _stop();
    } else {
      _openSection(next);
    }
  }

  void _openSection(int index) {
    if (!_ready) return;
    _hideControls();
    if (_index == index) return;
    final continuous = _continuous;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _saveTimer?.cancel();
    setState(() {
      _index = index;
      _vertical = GlobalKey();
      _verticalPage = 0;
      _lastScrollOffset = _scrollFraction = 0;
      _resumeOffset = null;
      _selection = '';
    });
    if (_auto && continuous != _continuous) _startAutomation();
    _save();
  }

  void _switchLayout() {
    if (!_ready) return;
    _stop();
    _hideControls();
    setState(() {
      _horizontal = !_horizontal;
      if (_horizontal) _resumeOffset ??= _lastScrollOffset;
    });
    _save();
  }

  Future<void> _contents() async {
    if (!_ready) return;
    _stop();
    final destination = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AnimatedBuilder(
        animation: widget.repository.policy,
        builder: (context, _) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: !_ready
              ? const Center(child: Text('内容策略已变更'))
              : _isPdf
              ? ListView(
                  children: [
                    if (_outline.isEmpty)
                      const ListTile(title: Text('此 PDF 没有目录，可按页浏览')),
                    ..._outlineTiles(context, _outline),
                  ],
                )
              : ListView.builder(
                  itemCount: _sections!.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(_sections![index].title),
                    selected: index == _index,
                    onTap: () => Navigator.pop(context, index),
                  ),
                ),
        ),
      ),
    );
    if (!mounted || !_ready) return;
    if (destination is int) {
      _openSection(destination);
    } else if (destination is PdfDest) {
      _hideControls();
      await _pdf.goToDest(destination);
    }
  }

  List<Widget> _outlineTiles(
    BuildContext context,
    List<PdfOutlineNode> nodes,
  ) => [
    for (final node in nodes) ...[
      ListTile(
        title: Text(node.title),
        onTap: node.dest == null
            ? null
            : () => Navigator.pop(context, node.dest),
      ),
      ..._outlineTiles(context, node.children),
    ],
  ];

  @override
  void dispose() {
    _automation.dispose();
    _saveTimer?.cancel();
    _save();
    _searcher?.dispose();
    _searchInput.dispose();
    _scroll.dispose();
    widget.repository.policy.removeListener(_onPolicyChanged);
    WidgetsBinding.instance.removeObserver(this);
    _systemUi.restore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _style.paper.palette(Theme.of(context).colorScheme);
    final toolbar = _controls || !_ready;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _manualTurn(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () =>
            _manualTurn(1),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          if (_ready && !_controls) _toggleControls();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: _isPdf ? null : palette.paper,
          body: SafeArea(
            top: !_style.immersive || !_ready,
            bottom: !_style.immersive || !_ready,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!_isPdf)
                  Positioned.fill(
                    child: ReaderPaperSurface(
                      palette: palette,
                      texture: _style.texture,
                    ),
                  ),
                Builder(builder: (context) => _readerContent(context, palette)),
                if (toolbar)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _readerToolbar(),
                  ),
                if (_ready && (_controls || !_style.immersive))
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Material(
                      elevation: 2,
                      child: SafeArea(top: false, child: _footerBar()),
                    ),
                  ),
                if (_ready && _style.immersive && !_controls) _readingStatus(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _readerToolbar() => Material(
    elevation: 2,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppBar(
          title: Text(_error == null ? widget.book.title : '电子书阅读'),
          actions: [
            if (_ready && !_isPdf)
              IconButton(
                tooltip: '切换横排／竖排',
                icon: const Icon(Icons.screen_rotation),
                onPressed: _switchLayout,
              ),
            IconButton(
              tooltip: '目录',
              onPressed: _ready ? _contents : null,
              icon: const Icon(Icons.list),
            ),
            IconButton(
              tooltip: '阅读样式',
              onPressed: _ready ? _settings : null,
              icon: const Icon(Icons.text_fields),
            ),
          ],
        ),
        if (_controls && _ready)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
            child: _searchBar(),
          ),
      ],
    ),
  );

  Widget _readerContent(BuildContext context, ReaderPalette palette) {
    if (_error case final message?) return Center(child: Text(message));
    if (!_validated) return const Center(child: CircularProgressIndicator());
    if (!_isPdf && _controls && _query.isNotEmpty) {
      return Padding(
        padding: EdgeInsets.only(
          top:
              MediaQuery.paddingOf(context).top +
              (AppBarTheme.of(context).toolbarHeight ?? kToolbarHeight) +
              64,
          bottom: MediaQuery.paddingOf(context).bottom + 48,
        ),
        child: _searchResults(_sections!),
      );
    }
    return Listener(
      onPointerDown: (_) => _stop(),
      onPointerSignal: (_) => _stop(),
      child: _isPdf
          ? _pdfView()
          : ReaderTapZones(
              horizontal: false,
              selectionActive: () => _selection.isNotEmpty,
              onTurn: _manualTurn,
              onMenu: _toggleControls,
              child: _epub(palette),
            ),
    );
  }

  void _manualTurn(int direction) {
    _stop();
    _next(direction);
  }

  Widget _readingStatus() => Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              tooltip: '上一页',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _manualTurn(-1),
            ),
            _pageLabel(),
            IconButton.filledTonal(
              tooltip: _auto ? '停止自动阅读' : '阅读菜单',
              icon: Icon(_auto ? Icons.pause : Icons.more_horiz),
              onPressed: _auto ? _stop : _toggleControls,
            ),
            IconButton.filledTonal(
              tooltip: '下一页',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _manualTurn(1),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _pageLabel() => Material(
    color: Theme.of(
      context,
    ).colorScheme.surfaceContainer.withValues(alpha: .86),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text('${_index + 1} / ${_chapters.length}'),
    ),
  );

  Future<void> _settings() async {
    _configuring = true;
    await showReaderSettings(
      context,
      _style.copyWith(autoEnabled: _auto),
      (settings) {
        if (!mounted || !_ready) return;
        if (settings.immersive != _style.immersive) {
          _systemUi.apply(settings.immersive);
        }
        final previous = _style;
        setState(() => _style = settings);
        if (!settings.autoEnabled) {
          _stop();
        } else if (!_auto ||
            previous.mode != settings.mode ||
            previous.autoSeconds != settings.autoSeconds) {
          _startAutomation();
        }
      },
      rich: true,
      pdf: _isPdf,
    );
    _configuring = false;
    if (mounted && _ready) {
      try {
        await widget.repository.store.write(
          'books_reader_preferences',
          _style.toJson(),
        );
      } on Exception {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('阅读设置保存失败，请重试')));
        }
      }
    }
  }

  Widget _pdfView() => PdfViewer.file(
    widget.file.path,
    controller: _pdf,
    initialPageNumber: _index + 1,
    params: PdfViewerParams(
      onDocumentLoadFinished: (_, succeeded) {
        if (mounted && !succeeded && _error == null) {
          setState(() => _error = '无法打开 PDF，文件可能损坏');
        }
      },
      onViewerReady: _pdfReady,
      onGeneralTap: (context, controller, details) {
        if (!_ready ||
            details.type != PdfViewerGeneralTapType.tap ||
            details.tapOn == PdfViewerPart.selectedText) {
          return false;
        }
        _toggleControls();
        return false;
      },
      onPageChanged: (page) {
        if (mounted && _ready && page != null) {
          setState(() => _index = page - 1);
          if (_query.isEmpty) _hideControls();
          _save();
        }
      },
      pagePaintCallbacks: [
        if (_searcher != null) _searcher!.pageTextMatchPaintCallback,
      ],
      linkHandlerParams: PdfLinkHandlerParams(onLinkTap: (link) {}),
    ),
  );

  Future<void> _pdfReady(
    PdfDocument document,
    PdfViewerController controller,
  ) async {
    if (!mounted || _error != null) return;
    if (document.pages.length != _chapters.length) {
      setState(() => _error = 'PDF 页数与已导入目录不一致');
      return;
    }
    setState(() {
      _searcher ??= PdfTextSearcher(controller);
      _index = (controller.pageNumber ?? _index + 1) - 1;
    });
    _save();
    if (_style.autoEnabled && !_auto) _startAutomation();
    try {
      final outline = await document.loadOutline();
      if (mounted && _ready) setState(() => _outline = outline);
    } on Exception {
      // Page navigation and search are available without an outline.
    }
  }

  Widget _searchBar() => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _searchInput,
          decoration: const InputDecoration(labelText: '全文搜索'),
          onChanged: (q) {
            final query = q.trim();
            setState(() {
              if (_query.isEmpty && query.isNotEmpty && !_isPdf) {
                _resumeOffset ??= _lastScrollOffset;
              }
              _query = query;
            });
            _searcher?.startTextSearch(query);
          },
        ),
      ),
      if (_isPdf && _searcher != null) ...[
        ListenableBuilder(
          listenable: _searcher!,
          builder: (_, _) => Text('${_searcher!.matches.length} 项'),
        ),
        IconButton(
          tooltip: '下个结果',
          onPressed: _searcher!.goToNextMatch,
          icon: const Icon(Icons.search),
        ),
        IconButton(
          tooltip: '放大',
          onPressed: () => _pdf.zoomUp(),
          icon: const Icon(Icons.zoom_in),
        ),
        IconButton(
          tooltip: '缩小',
          onPressed: () => _pdf.zoomDown(),
          icon: const Icon(Icons.zoom_out),
        ),
      ],
    ],
  );

  Widget _footerBar() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      IconButton(
        tooltip: '上一页',
        onPressed: () => _manualTurn(-1),
        icon: const Icon(Icons.chevron_left),
      ),
      Text('${_index + 1} / ${_chapters.length}'),
      IconButton(
        tooltip: '阅读菜单',
        onPressed: _toggleControls,
        icon: const Icon(Icons.more_horiz),
      ),
      IconButton(
        tooltip: '下一页',
        onPressed: () => _manualTurn(1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  void _restoreScroll() {
    if (_resumeOffset == null || _restoringScroll) return;
    _restoringScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoringScroll = false;
      if (!mounted || !_ready || !_scroll.hasClients || _resumeOffset == null) {
        return;
      }
      final position = _scroll.position;
      if (!position.hasContentDimensions ||
          position.maxScrollExtent == 0 && _resumeOffset! > 0) {
        return;
      }
      _scroll.jumpTo(_resumeOffset!.clamp(0.0, position.maxScrollExtent));
      _resumeOffset = null;
      _scrolled();
    });
  }

  Widget _searchResults(List<RichSection> sections) {
    final pattern = RegExp(
      RegExp.escape(_query),
      caseSensitive: false,
      unicode: true,
    );
    final matches = [
      for (final (index, section) in sections.indexed)
        if (pattern.firstMatch(section.text) case final match?) (index, match),
    ];
    if (matches.isEmpty) return const Center(child: Text('没有匹配的章节'));
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (_, i) {
        final (index, match) = matches[i];
        final section = sections[index];
        return ListTile(
          title: Text(section.title),
          subtitle: Text(
            section.text.substring(
              (match.start - 40).clamp(0, section.text.length),
              (match.end + 100).clamp(0, section.text.length),
            ),
          ),
          onTap: () => _openSection(index),
        );
      },
    );
  }

  Widget _epub(ReaderPalette palette) {
    final sections = _sections;
    if (sections == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final section = sections[_index];
    if (section.vertical && !_horizontal) {
      return ColoredBox(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.fromLTRB(_style.margin, 8, _style.margin, 22),
          child: VerticalBookText(
            key: _vertical,
            text: section.text,
            html: section.html,
            initialPage: _verticalPage,
            onPageChanged: (page) {
              _verticalPage = page;
              _save();
            },
            style: TextStyle(
              fontFamily: _style.family,
              fontSize: _style.fontSize,
              color: palette.ink,
            ),
            onBoundary: _crossSection,
          ),
        ),
      );
    }
    _restoreScroll();
    return ColoredBox(
      color: Colors.transparent,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _restoreScroll();
          return false;
        },
        child: SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(_style.margin, 8, _style.margin, 22),
          child: SelectionArea(
            onSelectionChanged: (selection) =>
                _selection = selection?.plainText ?? '',
            child: HtmlWidget(
              section.html,
              factoryBuilder: () => _EpubWidgetFactory(),
              textStyle: TextStyle(
                fontFamily: _style.family,
                fontSize: _style.fontSize,
                height: _style.lineHeight,
                color: palette.ink,
              ),
              onTapUrl: (_) => true,
              customStylesBuilder: (e) => e.localName == 'pre'
                  ? {
                      'white-space': 'pre',
                      'overflow': 'auto',
                      'font-family': 'monospace',
                    }
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _EpubWidgetFactory extends WidgetFactory with SvgFactory {}
