part of 'book_reader_page.dart';

extension _ReaderTools on _BookReaderPageState {
  Future<void> _showChapters() async {
    final selected = await showModalBottomSheet<BookChapter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AnimatedBuilder(
          animation: _books.policy,
          builder: (context, _) {
            final allowed = _books.bookAllowed(widget.book);
            final ordered = _reverse
                ? widget.chapters.reversed
                : widget.chapters;
            final visible = allowed
                ? ordered
                      .where(
                        (chapter) =>
                            chapter.title.contains(_chapterQuery) &&
                            _books.policy.textAllowed(chapter.title),
                      )
                      .toList()
                : <BookChapter>[];
            return _readerSheet(context, [
              ListTile(
                title: const Text('章节目录'),
                subtitle: Text('${visible.length} 章'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '上一章',
                      icon: const Icon(Icons.skip_previous),
                      onPressed: _canCross(-1)
                          ? () => Navigator.pop(
                              context,
                              widget.chapters[_index - 1],
                            )
                          : null,
                    ),
                    IconButton(
                      tooltip: '下一章',
                      icon: const Icon(Icons.skip_next),
                      onPressed: _canCross(1)
                          ? () => Navigator.pop(
                              context,
                              widget.chapters[_index + 1],
                            )
                          : null,
                    ),
                    IconButton(
                      tooltip: '倒序',
                      icon: const Icon(Icons.sort),
                      isSelected: _reverse,
                      onPressed: () => update(() => _reverse = !_reverse),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextFormField(
                  initialValue: _chapterQuery,
                  decoration: const InputDecoration(
                    hintText: '筛选章节',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) =>
                      update(() => _chapterQuery = value.trim()),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final chapter = visible[index];
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
            ]);
          },
        ),
      ),
    );
    if (mounted && selected != null && selected != _chapter) {
      await _open(selected);
    }
  }

  Future<void> _showFind() async {
    if (!_ready) return;
    _stopAutomation();
    final text = _text;
    final chapter = _chapter;
    final match = await showModalBottomSheet<TextRange>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AnimatedBuilder(
          animation: _books.policy,
          builder: (context, _) {
            final matches =
                _ready && _text == text && _books.bookAllowed(widget.book)
                ? _chapterMatches(text, _findQuery)
                : const <TextRange>[];
            return _readerSheet(context, [
              ListTile(
                title: const Text('章内查找'),
                subtitle: _findQuery.isEmpty
                    ? null
                    : Text(
                        matches.length == 301
                            ? '超过 300 处匹配'
                            : '${matches.length} 处匹配',
                      ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextFormField(
                  initialValue: _findQuery,
                  autofocus: true,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    hintText: '输入正文关键词',
                    counterText: '',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => update(() => _findQuery = value.trim()),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: math.min(300, matches.length),
                  itemBuilder: (context, index) {
                    final range = matches[index];
                    final start = _textBoundary(
                      text,
                      math.max(0, range.start - 24),
                    );
                    final end = _textBoundary(
                      text,
                      math.min(text.length, range.end + 42),
                    );
                    return ListTile(
                      title: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: text
                                  .substring(start, range.start)
                                  .replaceAll('\n', ' '),
                            ),
                            TextSpan(
                              text: text.substring(range.start, range.end),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: text
                                  .substring(range.end, end)
                                  .replaceAll('\n', ' '),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, range),
                    );
                  },
                ),
              ),
            ]);
          },
        ),
      ),
    );
    if (!mounted ||
        !_ready ||
        match == null ||
        _chapter != chapter ||
        _text != text) {
      return;
    }
    _showMatch(match);
  }

  Future<void> _addAnnotation() async {
    final chapter = _chapter;
    final position = _progress.value;
    final quote = _selection;
    var draft = '';
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: _books.policy,
        builder: (context, _) {
          if (!_ready || !_books.bookAllowed(widget.book)) {
            return AlertDialog(
              content: const Text('内容策略已变更'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            );
          }
          return AlertDialog(
            title: const Text('添加书签或笔记'),
            scrollable: true,
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(chapter.title),
                  if (quote.isNotEmpty)
                    Text(quote, maxLines: 4, overflow: TextOverflow.ellipsis),
                  TextField(
                    onChanged: (value) => draft = value,
                    maxLength: 2000,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: '留空保存书签；选中正文后可摘录',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, draft.trim()),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || !_ready || _chapter != chapter || note == null) return;
    try {
      _books.requireBook(widget.book, chapter);
      await _books.store.addAnnotation(widget.book, {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'chapter': chapter.id,
        'title': chapter.title,
        'position': position.fraction,
        'offset': ?position.offset,
        'quote': quote.length > 4000
            ? quote.substring(0, _textBoundary(quote, 4000))
            : quote,
        'note': note,
      });
      if (mounted) {
        _readerNotice('已保存书签与笔记');
      }
    } on Exception {
      if (mounted) {
        _readerNotice('保存失败，请重试');
      }
    }
  }

  Future<void> _annotations() async {
    try {
      var entries = await _books.store.annotations(widget.book);
      if (!mounted) return;
      final selected = await showModalBottomSheet<Map>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AnimatedBuilder(
            animation: _books.policy,
            builder: (context, _) => !_books.bookAllowed(widget.book)
                ? const Center(child: Text('当前内容策略限制访问此作品'))
                : SafeArea(
                    child: Column(
                      children: [
                        const ListTile(title: Text('书签与笔记')),
                        if (entries.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('选中正文可摘录，使用书签按钮记录当前位置'),
                          ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              if (!_books.policy.textAllowed(
                                '${entry['title']} ${entry['quote']} ${entry['note']}',
                              )) {
                                return const SizedBox.shrink();
                              }
                              return ListTile(
                                title: Text(entry['title'] as String? ?? ''),
                                subtitle: Text(
                                  [entry['quote'], entry['note']]
                                      .whereType<String>()
                                      .where((s) => s.isNotEmpty)
                                      .join('\n'),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => Navigator.pop(context, entry),
                                trailing: IconButton(
                                  tooltip: '删除记录',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    try {
                                      await _books.store.deleteAnnotation(
                                        widget.book,
                                        entry['id'] as String,
                                      );
                                      entries = await _books.store.annotations(
                                        widget.book,
                                      );
                                      if (context.mounted) update(() {});
                                    } on Exception {
                                      if (mounted) _readerNotice('删除书签失败，请重试');
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
      if (!mounted || selected == null) return;
      final chapter = widget.chapters
          .where((c) => c.id == selected['chapter'])
          .firstOrNull;
      if (chapter != null) {
        await _open(
          chapter,
          location: readerProgress(
            (selected['position'] as num? ?? 0).toDouble().clamp(0.0, 1.0),
            offset: selected['offset'] is int
                ? selected['offset'] as int
                : null,
          ),
        );
      }
    } on Exception {
      if (mounted) {
        _readerNotice('无法读取书签，请重试');
      }
    }
  }
}

Widget _readerSheet(BuildContext context, List<Widget> children) => Padding(
  padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
  child: FractionallySizedBox(
    heightFactor: .77,
    child: SafeArea(child: Column(children: children)),
  ),
);

List<TextRange> _chapterMatches(String text, String query) {
  if (query.isEmpty) return const [];
  final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
  return [
    for (final match in pattern.allMatches(text).take(301))
      TextRange(start: match.start, end: match.end),
  ];
}

int _textBoundary(String text, int index) {
  if (index >= text.length) return text.length;
  final code = text.codeUnitAt(index);
  return index > 0 && code >= 0xdc00 && code <= 0xdfff ? index - 1 : index;
}
