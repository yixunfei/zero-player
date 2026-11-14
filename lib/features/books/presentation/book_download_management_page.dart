import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../data/book_download_coordinator.dart';
import '../data/book_store.dart';
import '../domain/book.dart';
import '../domain/book_download_plan.dart';
import 'book_detail_page.dart';
import 'book_page_route.dart';

typedef _DownloadItem = ({
  BookShelfEntry entry,
  BookDownloadPlan? plan,
  Set<String> saved,
});

enum _DownloadFilter { all, running, pending, saved }

final class BookDownloadManagementPage extends StatefulWidget {
  const BookDownloadManagementPage({super.key, required this.services});
  final AppServices services;

  @override
  State<BookDownloadManagementPage> createState() =>
      _BookDownloadManagementPageState();
}

final class _BookDownloadManagementPageState
    extends State<BookDownloadManagementPage> {
  List<_DownloadItem> _items = [];
  Set<String> _activeIds = {};
  final Set<String> _busyIds = {};
  BookKind? _kind;
  _DownloadFilter _filter = _DownloadFilter.all;
  int _sequence = 0;
  bool _loading = true;
  String? _error;

  BookDownloadCoordinator get _manager => widget.services.bookDownloads;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_tasksChanged);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _manager.removeListener(_tasksChanged);
    super.dispose();
  }

  void _tasksChanged() {
    if (!mounted) return;
    final ids = _manager.activeTasks.map((task) => task.book.id).toSet();
    if (ids.length != _activeIds.length || !_activeIds.containsAll(ids)) {
      _activeIds = ids;
      unawaited(_reload());
    } else {
      setState(() {});
    }
  }

  Future<Set<String>> _saved(Book book) => switch (book.kind) {
    BookKind.text => widget.services.books.store.savedText(book),
    BookKind.comic => widget.services.books.store.savedImages(book),
    BookKind.audio => widget.services.books.audioFiles.saved(book),
  };

  Future<void> _reload() async {
    final sequence = ++_sequence;
    if (mounted) setState(() => _loading = true);
    try {
      final store = widget.services.books.store;
      final plans = await store.downloadPlans();
      final shelf = await store.shelf();
      final items = <_DownloadItem>[];
      final seen = <String>{};
      for (final entry in shelf) {
        final book = entry.book;
        if (book.sourceId == 'local' ||
            !widget.services.books.bookAllowed(book)) {
          continue;
        }
        final plan = plans[book.id];
        final active = _manager.active(book);
        final saved = await _saved(book);
        if (plan != null || active != null || saved.isNotEmpty) {
          items.add((entry: entry, plan: plan, saved: saved));
          seen.add(book.id);
        }
      }
      for (final task in _manager.activeTasks) {
        final book = task.book;
        if (seen.contains(book.id) || !widget.services.books.bookAllowed(book)) {
          continue;
        }
        items.add((
          entry: BookShelfEntry(book, task.chapters, null, 0, false, 0),
          plan: plans[book.id],
          saved: await _saved(book),
        ));
      }
      if (!mounted || sequence != _sequence) return;
      setState(() {
        _items = items;
        _activeIds = _manager.activeTasks.map((task) => task.book.id).toSet();
        _loading = false;
        _error = null;
      });
    } on Exception {
      if (mounted && sequence == _sequence) {
        setState(() {
          _loading = false;
          _error = '无法读取下载记录';
        });
      }
    }
  }

  Future<void> _action(Book book, Future<void> Function() action) async {
    if (!_busyIds.add(book.id)) return;
    setState(() {});
    try {
      await action();
      await _reload();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作未完成，请检查文件或内容权限')));
      }
    } finally {
      _busyIds.remove(book.id);
      if (mounted) setState(() {});
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _removePlan(Book book) async {
    if (!await _confirm('移除下载计划？', '已保存的章节仍会保留，可从书籍详情重新选择下载。')) return;
    await _action(book, () => _manager.removePlan(book));
  }

  Future<void> _deleteOffline(Book book) async {
    if (!await _confirm('删除离线内容？', '将删除这本书已下载的章节，保留书架记录和阅读进度。')) return;
    await _action(book, () async {
      await _manager.removePlan(book);
      if (book.kind == BookKind.audio) {
        await widget.services.books.audioFiles.removeSaved(book);
      } else {
        await widget.services.books.store.clearOffline(book);
      }
    });
  }

  Future<void> _open(Book book) async {
    await Navigator.of(context).push(
      BookPageRoute<void>(
        builder: (_) =>
            BookDetailPage(services: widget.services, initial: book),
      ),
    );
    if (mounted) await _reload();
  }

  List<_DownloadItem> get _visible => _items.where((item) {
    if (_kind != null && item.entry.book.kind != _kind) return false;
    final running = _manager.active(item.entry.book) != null;
    return switch (_filter) {
      _DownloadFilter.all => true,
      _DownloadFilter.running => running,
      _DownloadFilter.pending => !running && item.plan != null,
      _DownloadFilter.saved => !running && item.plan == null,
    };
  }).toList();

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('书籍下载管理'),
        actions: [
          IconButton(
            tooltip: '刷新下载记录',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _filters(),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _error != null
                ? Center(
                    child: TextButton(
                      onPressed: _reload,
                      child: Text('$_error，重试'),
                    ),
                  )
                : visible.isEmpty
                ? const Center(child: Text('暂无符合条件的下载'))
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, index) => _tile(visible[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filters() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<BookKind?>(
          value: _kind,
          items: const [
            DropdownMenuItem(value: null, child: Text('全部类型')),
            DropdownMenuItem(value: BookKind.text, child: Text('文字')),
            DropdownMenuItem(value: BookKind.comic, child: Text('漫画')),
            DropdownMenuItem(value: BookKind.audio, child: Text('听书')),
          ],
          onChanged: (value) => setState(() => _kind = value),
        ),
        DropdownButton<_DownloadFilter>(
          value: _filter,
          items: const [
            DropdownMenuItem(value: _DownloadFilter.all, child: Text('全部状态')),
            DropdownMenuItem(
              value: _DownloadFilter.running,
              child: Text('下载中'),
            ),
            DropdownMenuItem(
              value: _DownloadFilter.pending,
              child: Text('待续传'),
            ),
            DropdownMenuItem(value: _DownloadFilter.saved, child: Text('已保存')),
          ],
          onChanged: (value) =>
              setState(() => _filter = value ?? _DownloadFilter.all),
        ),
      ],
    ),
  );

  Widget _tile(_DownloadItem item) {
    final book = item.entry.book;
    final task = _manager.active(book);
    final busy = _busyIds.contains(book.id);
    final count = item.saved.length;
    final planned =
        item.plan?.chapterIds?.length ??
        (item.plan == null ? 0 : item.plan!.last - item.plan!.first + 1);
    final status = task != null
        ? '下载中 ${task.finished}/${task.total} · 已离线 $count 章'
        : item.plan != null
        ? '待续传 · 已离线 $count/$planned 章'
        : '已离线 $count 章';
    return ListTile(
      leading: Icon(switch (book.kind) {
        BookKind.text => Icons.menu_book_outlined,
        BookKind.comic => Icons.auto_stories_outlined,
        BookKind.audio => Icons.headphones_outlined,
      }),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (task != null && task.total > 0)
            LinearProgressIndicator(value: task.finished / task.total),
        ],
      ),
      onTap: () => _open(book),
      trailing: PopupMenuButton<String>(
        tooltip: '管理下载',
        enabled: !busy,
        onSelected: (action) {
          switch (action) {
            case 'pause':
              task?.pause();
            case 'resume':
              if (item.plan case final plan?) {
                _manager.start(book, item.entry.chapters, plan);
              }
            case 'remove':
              unawaited(_removePlan(book));
            case 'delete':
              unawaited(_deleteOffline(book));
          }
        },
        itemBuilder: (_) => [
          if (task != null)
            const PopupMenuItem(value: 'pause', child: Text('暂停')),
          if (task == null &&
              item.plan != null &&
              item.entry.chapters.isNotEmpty)
            const PopupMenuItem(value: 'resume', child: Text('继续下载')),
          if (item.plan != null)
            const PopupMenuItem(value: 'remove', child: Text('移除下载计划')),
          if (count > 0)
            const PopupMenuItem(value: 'delete', child: Text('删除离线内容')),
        ],
      ),
    );
  }
}
