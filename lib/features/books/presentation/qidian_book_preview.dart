import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../data/qidian_catalog.dart';
import '../domain/book.dart';
import 'book_links.dart';
import 'qidian_browser_import.dart';

final class QidianBookPreview extends StatefulWidget {
  const QidianBookPreview({
    super.key,
    required this.book,
    required this.catalog,
    required this.onOpen,
    required this.child,
  });

  final Book book;
  final QidianCatalog catalog;
  final VoidCallback onOpen;
  final Widget child;

  @override
  State<QidianBookPreview> createState() => _QidianBookPreviewState();
}

final class _QidianBookPreviewState extends State<QidianBookPreview> {
  Timer? _hover;
  CancellationToken? _token;
  QidianInfo? _info;
  bool _hovering = false;

  @override
  void didUpdateWidget(QidianBookPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id == widget.book.id &&
        identical(oldWidget.catalog, widget.catalog)) {
      return;
    }
    _hover?.cancel();
    _token?.cancel();
    _info = null;
    _hovering = false;
  }

  @override
  void dispose() {
    _hover?.cancel();
    _token?.cancel();
    super.dispose();
  }

  Future<void> _loadHover() async {
    if (!_hovering || _info != null) return;
    final token = _token = CancellationToken();
    try {
      final info = await widget.catalog.details(widget.book, token);
      if (mounted && !token.isCancelled) setState(() => _info = info);
    } on Exception {
      // The explicit information dialog can show the error and retry.
    }
  }

  bool get _showPreview => _hovering && widget.catalog.allows(widget.book);

  void _leave() {
    _hover?.cancel();
    _token?.cancel();
    setState(() => _hovering = false);
  }

  Future<void> _showInfo() async {
    _leave();
    final search = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _WorkInfoDialog(book: widget.book, catalog: widget.catalog),
    );
    if (mounted && search == true) widget.onOpen();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      setState(() => _hovering = true);
      _hover = Timer(const Duration(milliseconds: 450), _loadHover);
    },
    onExit: (_) => _leave(),
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_info?.cover case final cover? when cover.isNotEmpty)
          Positioned.fill(
            child: _WorkCover(
              catalog: widget.catalog,
              book: widget.book,
              cover: cover,
            ),
          ),
        if (_showPreview)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 38, 8, 8),
                  child: Text(
                    _hoverText(),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: 2,
          top: 2,
          child: IconButton.filledTonal(
            tooltip: '起点作品信息',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const Icon(Icons.info_outline),
            onPressed: _showInfo,
          ),
        ),
      ],
    ),
  );

  String _hoverText() {
    final facts = _facts(widget.book, _info);
    return facts.isEmpty ? '点按查看作品信息' : facts.join('\n');
  }
}

List<String> _facts(Book book, QidianInfo? info) {
  final values = {
    '作者': (info?.author ?? '').isNotEmpty ? info!.author : book.author,
    '状态': info?.status ?? '',
    '类型': (info?.category ?? '').isNotEmpty ? info!.category : book.category,
    '最新章节': (info?.latest ?? '').isNotEmpty ? info!.latest : book.latestChapter,
    '更新时间': info?.updated ?? '',
    '字数': info?.words ?? '',
    '总推荐': info?.totalRecommendations ?? '',
    '周推荐': info?.weeklyRecommendations ?? '',
  };
  return [
    for (final field in values.entries)
      if (field.value.isNotEmpty) '${field.key}  ${field.value}',
  ];
}

final class _WorkInfoDialog extends StatefulWidget {
  const _WorkInfoDialog({required this.book, required this.catalog});
  final Book book;
  final QidianCatalog catalog;

  @override
  State<_WorkInfoDialog> createState() => _WorkInfoDialogState();
}

final class _WorkInfoDialogState extends State<_WorkInfoDialog> {
  CancellationToken? _token;
  late Future<QidianInfo> _result = _load();
  bool _pickingPage = false;
  String? _importError;

  Future<QidianInfo> _load() {
    _token?.cancel();
    _importError = null;
    return widget.catalog.details(widget.book, _token = CancellationToken());
  }

  Future<void> _importPage() async {
    if (_pickingPage || !widget.catalog.allows(widget.book)) return;
    setState(() {
      _pickingPage = true;
      _importError = null;
    });
    try {
      final bytes = await pickQidianBrowserPage(
        context,
        widget.book.uri,
        allowed: () => mounted && widget.catalog.allows(widget.book),
      );
      if (!mounted || bytes == null) return;
      _token?.cancel();
      final token = _token = CancellationToken();
      setState(() {
        _result = widget.catalog.importDetails(widget.book, bytes, token);
      });
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _importError = error is FormatException ? error.message : '无法读取网页文件';
        });
      }
    } finally {
      if (mounted) setState(() => _pickingPage = false);
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.book.title),
    content: SizedBox(
      width: 400,
      child: FutureBuilder<QidianInfo>(
        future: _result,
        builder: (context, snapshot) {
          final facts = _facts(widget.book, snapshot.data);
          final error = snapshot.error;
          final cover = snapshot.data?.cover ?? '';
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cover.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: 120,
                      height: 160,
                      child: _WorkCover(
                        catalog: widget.catalog,
                        book: widget.book,
                        cover: cover,
                      ),
                    ),
                  ),
                for (final line in facts) Text(line),
                if (snapshot.connectionState != ConnectionState.done)
                  const LinearProgressIndicator(),
                if (_importError case final message?) Text(message),
                if (error != null) ...[
                  Text(switch (error) {
                    FormatException() => error.message,
                    RemoteFailure() => error.message,
                    _ => '暂时无法获取起点作品信息',
                  }),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: _pickingPage
                            ? null
                            : () => setState(() => _result = _load()),
                        child: const Text('重试'),
                      ),
                      if (widget.catalog.allows(widget.book))
                        TextButton(
                          onPressed: _pickingPage ? null : _importPage,
                          child: const Text('导入浏览器网页'),
                        ),
                    ],
                  ),
                ],
                if (snapshot.hasData && facts.isEmpty) const Text('起点未提供作品信息'),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => copyBookLink(context, widget.book.uri),
        child: const Text('复制起点作品链接'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('搜索各渠道'),
      ),
    ],
  );
}

/// Fetches the hi-res cover parsed from the work page, replacing the discovery
/// list's low-resolution thumbnail. Falls back to the underlying thumbnail when
/// the cover cannot be retrieved.
final class _WorkCover extends StatefulWidget {
  const _WorkCover({
    required this.catalog,
    required this.book,
    required this.cover,
  });
  final QidianCatalog catalog;
  final Book book;
  final String cover;

  @override
  State<_WorkCover> createState() => _WorkCoverState();
}

final class _WorkCoverState extends State<_WorkCover> {
  CancellationToken? _token;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_WorkCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cover != widget.cover ||
        oldWidget.book.id != widget.book.id ||
        !identical(oldWidget.catalog, widget.catalog)) {
      _load();
    }
  }

  Future<void> _load() async {
    _token?.cancel();
    final token = _token = CancellationToken();
    _bytes = null;
    final book = widget.book;
    final target = book.withDetails(
      Book(book.sourceId, book.kind, book.title, book.author, book.uri,
          cover: widget.cover),
    );
    try {
      final bytes = await widget.catalog.cover(target, token);
      if (mounted && !token.isCancelled) {
        setState(
          () => _bytes = bytes is Uint8List
              ? bytes
              : Uint8List.fromList(bytes),
        );
      }
    } on Exception {
      // Keep the list thumbnail when the work-page cover is unavailable.
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _bytes == null
      ? const SizedBox.shrink()
      : ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.memory(
            _bytes!,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );
}
