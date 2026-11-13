import 'package:flutter/material.dart';

import '../data/book_shelf_lists.dart';
import '../data/book_store.dart';
import '../data/books_repository.dart';
import '../domain/book.dart';
import 'book_cover.dart';

const _labels = {
  ShelfListKind.group: '分组',
  ShelfListKind.collection: '集合',
  ShelfListKind.list: '书单',
};

class BookShelfView extends StatefulWidget {
  const BookShelfView({
    super.key,
    required this.repository,
    required this.kind,
    required this.entries,
    required this.onOpen,
    required this.onFollowChanged,
    required this.onRefresh,
    required this.checking,
  });
  final BooksRepository repository;
  final BookKind kind;
  final List<BookShelfEntry> entries;
  final ValueChanged<Book> onOpen;
  final VoidCallback onFollowChanged;
  final Future<void> Function() onRefresh;
  final bool checking;

  @override
  State<BookShelfView> createState() => _BookShelfViewState();
}

class _BookShelfViewState extends State<BookShelfView> {
  List<ShelfList> _lists = [];
  String _selected = '';
  bool _following = false;
  BookShelfLists get _store =>
      BookShelfLists(widget.repository.store, widget.kind);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final lists = await _store.load();
    if (mounted) {
      setState(() {
        _lists = lists;
        if (!lists.any((list) => list.id == _selected)) _selected = '';
      });
    }
  }

  Future<void> _edit(ShelfListKind kind, [ShelfList? list]) async {
    var name = list?.name ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${list == null ? '新建' : '重命名'}${_labels[kind]}'),
        content: TextFormField(
          initialValue: name,
          maxLength: 60,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
          onChanged: (value) => name = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    try {
      await _store.save(result, kind, id: list?.id);
      await _reload();
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _assign(Book book) async {
    if (_lists.isEmpty) {
      await _edit(ShelfListKind.group);
      if (!mounted || _lists.isEmpty) return;
    }
    final selected = {
      for (final list in _lists)
        if (list.books.contains(book.id)) list.id,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('归入分组、集合或书单'),
          content: SizedBox(
            width: 450,
            height: 300,
            child: ListView(
              children: [
                for (final list in _lists)
                  CheckboxListTile(
                    title: Text(list.name),
                    subtitle: Text(_labels[list.kind]!),
                    value: selected.contains(list.id),
                    onChanged: (value) => update(() {
                      if (value == true) {
                        if (list.kind == ShelfListKind.group) {
                          selected.removeAll(
                            _lists
                                .where(
                                  (item) => item.kind == ShelfListKind.group,
                                )
                                .map((item) => item.id),
                          );
                        }
                        selected.add(list.id);
                      } else {
                        selected.remove(list.id);
                      }
                    }),
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true || !widget.repository.bookAllowed(book)) {
      return;
    }
    await _store.assign(book, selected);
    await _reload();
  }

  Future<void> _bookAction(BookShelfEntry entry, String action) async {
    if (!widget.repository.bookAllowed(entry.book)) return;
    if (action == 'lists') {
      await _assign(entry.book);
      return;
    }
    await widget.repository.store.saveBook(
      entry.book,
      following: !entry.following,
    );
    if (mounted) widget.onFollowChanged();
  }

  @override
  Widget build(BuildContext context) {
    final list = _lists.where((item) => item.id == _selected).firstOrNull;
    final entries = widget.entries
        .where(
          (entry) =>
              (!_following || entry.following) &&
              (list == null || list.books.contains(entry.book.id)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: _toolbar(list),
        ),
        if (widget.checking) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('这里还没有作品'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, index) => _tile(entries[index]),
                ),
        ),
      ],
    );
  }

  Widget _toolbar(ShelfList? list) => Wrap(
    spacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: DropdownButton<String>(
          isExpanded: true,
          value: _selected,
          items: [
            const DropdownMenuItem(value: '', child: Text('全部书籍')),
            for (final item in _lists)
              DropdownMenuItem(
                value: item.id,
                child: Text(
                  '${_labels[item.kind]} · ${item.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => setState(() => _selected = value ?? ''),
        ),
      ),
      FilterChip(
        label: const Text('追更'),
        selected: _following,
        onSelected: (value) => setState(() => _following = value),
      ),
      IconButton(
        tooltip: '检查追更',
        onPressed: widget.checking ? null : widget.onRefresh,
        icon: const Icon(Icons.refresh),
      ),
      PopupMenuButton<ShelfListKind>(
        tooltip: '新建书架列表',
        icon: const Icon(Icons.add),
        onSelected: _edit,
        itemBuilder: (_) => [
          for (final type in ShelfListKind.values)
            PopupMenuItem(value: type, child: Text('新建${_labels[type]}')),
        ],
      ),
      if (list != null)
        PopupMenuButton<bool>(
          tooltip: '管理当前列表',
          onSelected: (rename) async {
            if (rename) {
              await _edit(list.kind, list);
            } else {
              await _store.delete(list.id);
              await _reload();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: true, child: Text('重命名')),
            PopupMenuItem(value: false, child: Text('删除列表')),
          ],
        ),
    ],
  );

  Widget _tile(BookShelfEntry entry) {
    final book = entry.book;
    final last = entry.chapters
        .where((chapter) => chapter.id == entry.last)
        .firstOrNull;
    final latest = entry.chapters.lastOrNull;
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 54,
        child: BookCover(book: book, repository: widget.repository),
      ),
      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          book.author,
          if (last != null) last.title,
          if (entry.newChapters > 0 && latest != null)
            '更新 ${entry.newChapters} 章 · ${latest.title}'
          else if (entry.following)
            '追更中',
        ].where((value) => value.isNotEmpty).join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => widget.onOpen(book),
      trailing: PopupMenuButton<String>(
        tooltip: '书架操作',
        onSelected: (action) => _bookAction(entry, action),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'lists', child: Text('归入分组、集合或书单')),
          if (book.sourceId != 'local')
            PopupMenuItem(
              value: 'follow',
              child: Text(entry.following ? '取消追更' : '加入追更'),
            ),
        ],
      ),
    );
  }
}
