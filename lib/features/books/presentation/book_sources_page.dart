import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../supervision/presentation/sensitive_action.dart';
import '../data/book_import.dart';
import '../data/book_store.dart';
import '../domain/book.dart';

final class BookSourcesPage extends StatefulWidget {
  const BookSourcesPage({
    super.key,
    required this.services,
    required this.kind,
  });
  final AppServices services;
  final BookKind kind;
  @override
  State<BookSourcesPage> createState() => _BookSourcesPageState();
}

final class _BookSourcesPageState extends State<BookSourcesPage> {
  List<BookSourceEntry> _entries = [];
  bool _busy = false, _favorites = false;
  String _query = '';
  CancellationToken? _token;
  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _run(() async {});
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool protected = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (protected) {
        await runSensitive(
          context,
          _services.supervision,
          SensitiveOperation.channels,
          action,
        );
      } else {
        await action();
      }
    } on FormatException catch (error) {
      _notice(error.message);
    } on RemoteFailure catch (error) {
      _notice(error.message);
    } catch (_) {
      _notice('操作未完成，请重试');
    } finally {
      try {
        final entries = await _services.books.sources(widget.kind);
        if (mounted) setState(() => _entries = entries);
      } catch (_) {
        _notice('无法读取来源清单');
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _prompt(
    String label, {
    String initial = '',
    int limit = 80,
  }) async {
    var value = initial;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextFormField(
          initialValue: initial,
          maxLength: limit,
          autofocus: true,
          onChanged: (text) => value = text,
          onFieldSubmitted: (text) => Navigator.pop(context, text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() => _run(() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: '来源 JSON', extensions: ['json']),
      ],
    );
    if (file == null || !mounted) return;
    if (await file.length() > 8 * 1024 * 1024) {
      throw const FormatException('来源文件超过 8 MiB');
    }
    final input = await File(file.path).readAsString();
    await _applyImport(input);
  }, protected: true);

  Future<void> _importAddress() async {
    final address = await _prompt('来源 JSON 的 HTTPS 直链', limit: 2048);
    if (!mounted || address == null || address.isEmpty) return;
    await _run(() async {
      final token = _token = CancellationToken();
      try {
        await _applyImport(
          await _services.books.sourceDocument(address, token),
        );
      } finally {
        setStateIfMounted(() => _token = null);
      }
    }, protected: true);
  }

  Future<void> _applyImport(String input) async {
    final parsed = parseBookSources(input);
    final result = await _services.books.importSources(parsed.sources);
    _notice(
      '导入 ${result.added} 个，重复 ${result.duplicates + parsed.duplicates} 个，'
      '拒绝 ${parsed.rejected + parsed.sources.length - result.added - result.duplicates} 个',
    );
  }

  Future<void> _addFeed() async {
    final url = await _prompt('RSS / Atom 地址', limit: 2048);
    if (!mounted || url == null || url.isEmpty) return;
    final name = await _prompt('订阅名称');
    if (!mounted || name == null || name.isEmpty) return;
    final host = widget.kind == BookKind.audio
        ? await _prompt('音频 CDN 域名（同站可留空）', limit: 250)
        : '';
    if (!mounted || host == null) return;
    await _run(() async {
      final source = BookSource.fromJson({
        'name': name,
        'url': url,
        'kind': widget.kind.name,
        'format': 'feed',
        'group': '订阅',
        if (host.isNotEmpty) 'mediaHosts': [host],
      });
      final result = await _services.books.importSources([source]);
      _notice(
        result.added == 1
            ? '已添加，请检测后启用'
            : result.duplicates == 1
            ? '已有该订阅'
            : '该来源受内容策略限制',
      );
    }, protected: true);
  }

  Future<void> _probe(BookSource source) async {
    final query = source.format == BookFormat.feed
        ? ''
        : await _prompt('检测用书名', initial: source.sample);
    if (!mounted || query == null) return;
    await _run(() async {
      final token = _token = CancellationToken();
      try {
        await _services.books.probe(source, query, token);
      } finally {
        if (identical(token, _token)) setStateIfMounted(() => _token = null);
      }
    }, protected: true);
  }

  void setStateIfMounted(VoidCallback update) {
    if (mounted) setState(update);
  }

  @override
  Widget build(BuildContext context) {
    final list =
        _entries
            .where(
              (entry) =>
                  (!_favorites || entry.favorite) &&
                  '${entry.source.name} ${entry.group} ${entry.source.endpoint.host}'
                      .toLowerCase()
                      .contains(_query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.group.compareTo(b.group));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind == BookKind.audio ? '听书源' : '阅读源'),
        actions: [
          if (_token != null)
            IconButton(
              tooltip: '取消检测',
              onPressed: () => _token?.cancel(),
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          IconButton(
            tooltip: '添加 RSS / Atom',
            onPressed: _busy ? null : _addFeed,
            icon: const Icon(Icons.rss_feed),
          ),
          IconButton(
            tooltip: '导入来源 JSON',
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: '从链接导入来源 JSON',
            onPressed: _busy ? null : _importAddress,
            icon: const Icon(Icons.link),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: '筛选名称、分组或域名',
                prefixIcon: const Icon(Icons.filter_alt_outlined),
                suffixIcon: IconButton(
                  tooltip: '仅收藏源',
                  isSelected: _favorites,
                  onPressed: () => setState(() => _favorites = !_favorites),
                  icon: const Icon(Icons.star_outline),
                  selectedIcon: const Icon(Icons.star),
                ),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('没有符合条件的来源'))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, index) => _tile(list[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BookSourceEntry entry) {
    final source = entry.source;
    return ListTile(
      leading: IconButton(
        tooltip: entry.favorite ? '取消收藏源' : '收藏源',
        icon: Icon(entry.favorite ? Icons.star : Icons.star_outline),
        onPressed: _busy
            ? null
            : () => _run(
                () => _services.books.saveSource(source, {
                  'favorite': !entry.favorite,
                }),
                protected: true,
              ),
      ),
      title: Text(source.name),
      subtitle: Text(
        [
          if (source.builtin) '内置',
          if (entry.group.isNotEmpty) entry.group,
          source.endpoint.host,
          if (entry.health.isNotEmpty) entry.health,
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: entry.enabled,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () =>
                        _services.books.saveSource(source, {'enabled': value}),
                    protected: true,
                  ),
          ),
          PopupMenuButton<String>(
            tooltip: '来源操作',
            enabled: !_busy,
            onSelected: (value) async {
              switch (value) {
                case 'probe':
                  await _probe(source);
                case 'group':
                  final group = await _prompt(
                    '分组名称',
                    initial: entry.group,
                    limit: 60,
                  );
                  if (mounted && group != null) {
                    await _run(
                      () =>
                          _services.books.saveSource(source, {'group': group}),
                      protected: true,
                    );
                  }
                case 'remove':
                  await _run(
                    () => _services.books.removeSource(source),
                    protected: true,
                  );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'probe', child: Text('检测')),
              const PopupMenuItem(value: 'group', child: Text('修改分组')),
              if (!source.builtin)
                const PopupMenuItem(value: 'remove', child: Text('移除渠道')),
            ],
          ),
        ],
      ),
    );
  }
}
