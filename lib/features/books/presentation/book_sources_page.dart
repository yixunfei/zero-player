import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../supervision/presentation/sensitive_action.dart';
import '../data/aoaostar_book_catalog.dart';
import '../data/book_import.dart';
import '../data/book_store.dart';
import '../data/books_repository.dart';
import '../domain/book.dart';
import 'book_links.dart';

enum _SourceAction { catalog, file, link, feed }

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
  bool? _enabled;
  String _query = '';
  bool _selecting = false;
  final _selected = <String>{};
  CancellationToken? _token;
  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _services.contentPolicy.addListener(_policyChanged);
    _run(_services.books.ensureCatalog);
  }

  @override
  void dispose() {
    _token?.cancel();
    _services.contentPolicy.removeListener(_policyChanged);
    super.dispose();
  }

  void _policyChanged() {
    _token?.cancel();
    setState(() {
      _entries = [];
      _selected.clear();
    });
    if (!_busy) _run(() async {});
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
        const XTypeGroup(
          label: 'Legado 书源或备份',
          extensions: ['json', 'txt', 'zip'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    final token = _token = CancellationToken();
    final path = file.path;
    final parsed = await readBookSourceFile(path);
    token.check();
    if (!mounted) return;
    final result = await _services.books.importSources(
      parsed.sources,
      token: token,
    );
    _importNotice(parsed, result);
  }, protected: true);

  Future<void> _importAddress() async {
    final address = await _prompt('Legado 导入链接、来源 JSON 或源仓库详情页', limit: 4096);
    if (!mounted || address == null || address.isEmpty) return;
    final url = Uri.tryParse(address);
    if (url != null &&
        url.scheme == 'https' &&
        url.userInfo.isEmpty &&
        ((url.host == 'github.com' &&
                const {
                  '/aoaostar/legado',
                  '/aoaostar/legado/',
                  '/aoaostar/legado/tree/release',
                }.contains(url.path)) ||
            (url.host == 'legado.aoaostar.com' &&
                const {'', '/'}.contains(url.path)))) {
      await _importCatalog();
      return;
    }
    await _subscribe(address);
  }

  Future<void> _importCatalog() => _run(() async {
    final catalog = await AoaoStarBookCatalog.load();
    if (!mounted) return;
    final packId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('aoaostar/legado 书源包'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('书源包随应用提供。新增渠道默认停用，可检测后启用。'),
                const Divider(),
                for (final pack in catalog.packs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(pack.name),
                    subtitle: Text('${pack.count} 条原始记录'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, pack.id),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'all'),
            child: Text('导入全部 ${catalog.packs.length} 包'),
          ),
        ],
      ),
    );
    if (!mounted || packId == null) return;
    final token = _token = CancellationToken();
    setState(() {});
    try {
      final result = await _services.books.importCatalog(
        catalog,
        token,
        packId: packId == 'all' ? null : packId,
      );
      _importNotice(result.parsed, result.changes);
    } finally {
      setStateIfMounted(() => _token = null);
    }
  }, protected: true);

  Future<void> _subscribe(String address) => _run(() async {
    final token = _token = CancellationToken();
    setStateIfMounted(() {});
    try {
      final result = await _services.books.subscribe(address, token);
      _importNotice(result.parsed, result.changes);
    } finally {
      setStateIfMounted(() => _token = null);
    }
  }, protected: true);

  void _importNotice(BookSourceImport parsed, BookImportChanges changes) {
    _notice(
      [
        '新增 ${changes.added}',
        if (changes.updated > 0) '更新 ${changes.updated}',
        '重复 ${changes.duplicates + parsed.duplicates}',
        if (parsed.rejected > 0) '不兼容 ${parsed.rejected}${parsed.issueSummary}',
        if (changes.skipped > 0) '受黑名单、内容策略或容量限制 ${changes.skipped}',
      ].join('，'),
    );
  }

  Future<void> _subscriptions() async {
    final entries = await _services.books.subscriptions();
    if (!mounted) return;
    final choice =
        await showDialog<({BookSourceSubscription entry, bool refresh})>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('书源订阅'),
            content: SizedBox(
              width: 520,
              height: 280,
              child: entries.isEmpty
                  ? const Center(child: Text('还没有导入订阅链接'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          title: Text(entry.url.host),
                          subtitle: Text(
                            '${entry.url.path}\n最近核对 ${entry.count} 个源',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: PopupMenuButton<bool>(
                            tooltip: '订阅操作',
                            onSelected: (refresh) => Navigator.pop(context, (
                              entry: entry,
                              refresh: refresh,
                            )),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: true, child: Text('刷新订阅')),
                              PopupMenuItem(
                                value: false,
                                child: Text('移除订阅链接'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
    if (!mounted || choice == null) return;
    if (choice.refresh) {
      await _subscribe(choice.entry.url.toString());
    } else {
      await _run(
        () => _services.books.removeSubscription(choice.entry),
        protected: true,
      );
    }
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

  Future<void> _blacklist() async {
    final blocked = await _services.books.store.blockedSources();
    if (!mounted) return;
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('书源黑名单'),
        content: SizedBox(
          width: 440,
          height: 280,
          child: blocked.isEmpty
              ? const Center(child: Text('暂无屏蔽书源'))
              : ListView(
                  children: [
                    for (final entry in blocked.entries.where(
                      (entry) =>
                          _services.contentPolicy.textAllowed(entry.value),
                    ))
                      ListTile(
                        title: Text(entry.value),
                        trailing: TextButton(
                          onPressed: () => Navigator.pop(context, entry.key),
                          child: const Text('解除屏蔽'),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
    if (mounted && id != null) {
      await _run(() => _services.books.unblockSource(id), protected: true);
    }
  }

  Future<void> _batch(bool enabled) async {
    final ids = Set<String>.of(_selected);
    await _run(() async {
      await _services.books.setSourcesEnabled(widget.kind, ids, enabled);
      setStateIfMounted(() {
        _selected.clear();
        _selecting = false;
      });
    }, protected: true);
  }

  Widget _selectionTools(List<BookSourceEntry> visible) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Wrap(
      spacing: 8,
      children: [
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _selected.addAll(visible.map((entry) => entry.source.id));
                }),
          child: const Text('全选筛选结果'),
        ),
        TextButton(
          onPressed: _selected.isEmpty ? null : () => setState(_selected.clear),
          child: Text('清空 ${_selected.length} 项'),
        ),
        TextButton(
          onPressed: _busy || _selected.isEmpty ? null : () => _batch(true),
          child: const Text('一键启用'),
        ),
        TextButton(
          onPressed: _busy || _selected.isEmpty ? null : () => _batch(false),
          child: const Text('一键停用'),
        ),
      ],
    ),
  );

  Widget _restoreControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _services.books.restoreDefaultSources(widget.kind),
                  protected: true,
                ),
          icon: const Icon(Icons.restore),
          label: const Text('一键还原默认渠道'),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('恢复内置启用状态，停用额外渠道；保留收藏、书架、下载与黑名单。'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final list =
        _entries
            .where(
              (entry) =>
                  (!_favorites || entry.favorite) &&
                  (_enabled == null || entry.enabled == _enabled) &&
                  '${entry.source.name} ${entry.group} ${entry.source.endpoint.host}'
                      .toLowerCase()
                      .contains(query),
            )
            .toList()
          ..sort((a, b) {
            if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
            if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
            return a.source.name.compareTo(b.source.name);
          });
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind == BookKind.audio ? '听书源' : '网络小说渠道'),
        actions: [
          IconButton(
            tooltip: _selecting ? '退出批量选择' : '批量选择',
            icon: Icon(_selecting ? Icons.close : Icons.checklist),
            onPressed: _busy
                ? null
                : () => setState(() {
                    _selecting = !_selecting;
                    _selected.clear();
                  }),
          ),
          IconButton(
            tooltip: '书源黑名单',
            icon: const Icon(Icons.block),
            onPressed: _busy || _services.supervision.enabled
                ? null
                : _blacklist,
          ),
          if (_token != null)
            IconButton(
              tooltip: '取消操作',
              onPressed: () => _token?.cancel(),
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          PopupMenuButton<_SourceAction>(
            tooltip: '导入书源',
            enabled: !_busy,
            icon: const Icon(Icons.add),
            onSelected: (action) => switch (action) {
              _SourceAction.catalog => _importCatalog(),
              _SourceAction.file => _import(),
              _SourceAction.link => _importAddress(),
              _SourceAction.feed => _addFeed(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _SourceAction.catalog,
                child: Text('内置 Legado 书源包'),
              ),
              PopupMenuItem(value: _SourceAction.file, child: Text('导入来源文件')),
              PopupMenuItem(
                value: _SourceAction.link,
                child: Text('导入 Legado 链接'),
              ),
              PopupMenuItem(
                value: _SourceAction.feed,
                child: Text('添加 RSS / Atom'),
              ),
            ],
          ),
          IconButton(
            tooltip: '管理书源订阅',
            onPressed: _busy ? null : _subscriptions,
            icon: const Icon(Icons.subscriptions_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          _restoreControls(),
          _filters(),
          if (_selecting) _selectionTools(list),
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

  Widget _filters() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final (value, label) in const [
              (null, '全部'),
              (true, '已启用'),
              (false, '已停用'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _enabled == value,
                onSelected: (_) => setState(() => _enabled = value),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _sourceActions(BookSourceEntry entry) {
    final source = entry.source;
    return PopupMenuButton<String>(
      tooltip: '来源操作',
      enabled: !_busy,
      onSelected: (value) async {
        switch (value) {
          case 'copy':
            await copyBookLink(context, source.endpoint);
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
                () => _services.books.saveSource(source, {'group': group}),
                protected: true,
              );
            }
          case 'remove':
            await _run(
              () => _services.books.removeSource(source),
              protected: true,
            );
          case 'block':
            await _run(
              () => _services.books.blockSource(source),
              protected: true,
            );
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'copy', child: Text('复制渠道链接')),
        const PopupMenuItem(value: 'probe', child: Text('检测')),
        const PopupMenuItem(value: 'group', child: Text('修改分组')),
        const PopupMenuItem(value: 'remove', child: Text('删除书源')),
        const PopupMenuItem(value: 'block', child: Text('屏蔽并加入黑名单')),
      ],
    );
  }

  Widget _tile(BookSourceEntry entry) {
    final source = entry.source;
    if (_selecting) {
      return CheckboxListTile(
        value: _selected.contains(source.id),
        title: Text(source.name),
        subtitle: Text(
          '${entry.enabled ? '已启用' : '已停用'} · ${source.endpoint.host}',
        ),
        onChanged: _busy
            ? null
            : (value) => setState(() {
                if (value == true) {
                  _selected.add(source.id);
                } else {
                  _selected.remove(source.id);
                }
              }),
      );
    }
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
          if (entry.fromCatalog) 'aoaostar/legado',
          if (source.legado != null) 'Legado',
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
          _sourceActions(entry),
        ],
      ),
    );
  }
}
