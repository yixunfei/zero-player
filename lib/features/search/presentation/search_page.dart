import 'dart:async';
import 'package:flutter/material.dart' hide SearchController;
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../catalog/domain/catalog_item.dart';
import '../application/search_controller.dart';
import 'search_status_panel.dart';
import '../../catalog/presentation/source_choices.dart';

final class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.services,
    this.initial = '',
    this.preferredSourceId,
  });
  final AppServices services;
  final String initial;
  final String? preferredSourceId;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

final class _SearchPageState extends State<SearchPage> {
  late final SearchController controller;
  late final TextEditingController text;
  late Future<List<String>> history;
  final _inputFocus = FocusNode();
  String? _preferredId;
  late Future<String?> _preferredName;
  bool _onlyPreferred = false;
  @override
  void initState() {
    super.initState();
    controller = SearchController(
      widget.services.sources,
      widget.services.network,
      widget.services.history,
    );
    text = TextEditingController(text: widget.initial);
    history = widget.services.history.searches();
    _readPreferred();
    if (widget.initial.isNotEmpty) unawaited(_search());
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial ||
        oldWidget.preferredSourceId != widget.preferredSourceId) {
      _readPreferred();
      text.text = widget.initial;
      unawaited(_search());
    }
  }

  void _readPreferred() {
    _preferredId = widget.preferredSourceId ?? widget.services.searchSourceId;
    if (_preferredId == null) _onlyPreferred = false;
    _preferredName = _preferredId == null
        ? Future.value(null)
        : widget.services.sources
              .find(_preferredId!)
              .then((s) => s?.displayName);
  }

  Future<void> _search() => perform(context, () async {
    await controller.search(
      text.text,
      filterAdult: widget.services.contentPolicy.filterAdult,
      concurrency: widget.services.settings.value.searchConcurrency,
      preferredSourceId: _preferredId,
      onlyPreferred: _onlyPreferred,
    );
    if (mounted) {
      final updatedHistory = widget.services.history.searches();
      setState(() {
        history = updatedHistory;
      });
    }
  });

  Widget _scope() => FutureBuilder<String?>(
    future: _preferredName,
    builder: (context, snapshot) =>
        snapshot.data == null ||
            (_preferredId != null &&
                !widget.services.contentPolicy.sourceIdAllowed(_preferredId!))
        ? const SizedBox.shrink()
        : Wrap(
            spacing: 8,
            children: [
              for (final only in [false, true])
                ChoiceChip(
                  label: Text(only ? '仅当前来源' : '全站 · 优先 ${snapshot.data}'),
                  selected: _onlyPreferred == only,
                  onSelected: controller.loading
                      ? null
                      : (_) {
                          setState(() => _onlyPreferred = only);
                          if (text.text.trim().isNotEmpty) unawaited(_search());
                        },
                ),
            ],
          ),
  );
  @override
  void dispose() {
    controller.dispose();
    text.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: context.canPop(),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancelOrBack,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _inputFocus.requestFocus,
      },
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          children: [
            _searchBar(),
            _scope(),
            if (controller.loading) const LinearProgressIndicator(),
            if (controller.query.isEmpty) _history(),
            SearchStatusPanel(controller: controller),
            Expanded(
              child: controller.items.isEmpty
                  ? EmptyState(
                      controller.loading ? '正在逐源搜索' : '还没有搜索结果',
                      controller.error ??
                          (controller.loading
                              ? '结果会随来源响应陆续出现'
                              : controller.query.isEmpty
                              ? '输入片名，或选择搜索记录'
                              : '未找到匹配内容，可缩短关键词或切换搜索范围'),
                      action: TextButton(
                        onPressed: () => context.push('/sources'),
                        child: const Text('管理视频源'),
                      ),
                    )
                  : PosterGrid(
                      children: [
                        for (final group in controller.groups.values)
                          PosterCard(
                            title: group.first.title,
                            description: group.first.description,
                            poster:
                                group
                                    .where((i) => i.poster.isNotEmpty)
                                    .firstOrNull
                                    ?.poster ??
                                '',
                            subtitle:
                                '${group.first.year} ${group.first.remarks} · ${group.map((i) => i.sourceId).toSet().length} 个来源',
                            onTap: () => _choose(group),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _searchBar() => Padding(
    padding: const EdgeInsets.all(20),
    child: Row(
      children: [
        IconButton(
          tooltip: '返回上一页 (Esc / Alt+←)',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: TextField(
            controller: text,
            focusNode: _inputFocus,
            autofocus: true,
            onSubmitted: (_) => _search(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '输入影片名称',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: '清空输入',
                onPressed: () {
                  text.clear();
                  controller.clear();
                  _inputFocus.requestFocus();
                },
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: controller.loading
              ? () => setState(controller.cancel)
              : _search,
          child: Text(controller.loading ? '停止' : '搜索'),
        ),
      ],
    ),
  );

  void _cancelOrBack() {
    if (controller.loading) {
      setState(controller.cancel);
    } else {
      _back();
    }
  }

  void _back() {
    controller.cancel();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Widget _history() => FutureBuilder(
    future: history,
    builder: (context, snapshot) => Wrap(
      spacing: 8,
      children: [
        for (final query in snapshot.data ?? <String>[])
          ActionChip(
            label: Text(query),
            onPressed: () {
              text.text = query;
              _search();
            },
          ),
        if (snapshot.data?.isNotEmpty ?? false)
          ActionChip(
            label: const Text('清空搜索记录'),
            onPressed: () async {
              await widget.services.history.clearSearches();
              if (mounted) {
                setState(() {
                  history = widget.services.history.searches();
                });
              }
            },
          ),
      ],
    ),
  );
  Future<void> _choose(List<CatalogItem> items) async {
    final selected = await showDialog<CatalogItem>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(items.first.title),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SourceChoices(
              services: widget.services,
              items: items,
              onSelected: (item) => Navigator.pop(context, item),
              onBlock: controller.blockSource,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      context.push(
        '/detail/${selected.sourceId}/${Uri.encodeComponent(selected.id)}',
      );
    }
  }
}
