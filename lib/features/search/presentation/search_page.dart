import '../application/search_options.dart';
import 'advanced_search_dialog.dart';
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
import '../../catalog/presentation/source_choices_dialog.dart';

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
  SearchOptions _options = const SearchOptions();
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
    final preferred =
        widget.preferredSourceId ?? widget.services.searchSourceId;
    _preferredId = preferred == null || preferred.isEmpty ? null : preferred;
    _onlyPreferred = false;
    _preferredName = _preferredId == null
        ? Future.value(null)
        : widget.services.sources
              .find(_preferredId!)
              .then((s) => s?.displayName);
  }

  Future<void> _search() => perform(context, () async {
    _inputFocus.unfocus();
    await controller.search(
      text.text,
      filterAdult: widget.services.contentPolicy.filterAdult,
      concurrency: widget.services.settings.value.searchConcurrency,
      preferredSourceId: _preferredId,
      onlyPreferred: _onlyPreferred,
      options: _options,
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
                  label: Text(
                    only ? '仅当前来源' : '全渠道 · 优先 ${snapshot.data}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
        builder: (context, _) => CustomScrollView(
          key: const ValueKey('search-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _searchBar(),
                  _scope(),
                  if (controller.loading) const LinearProgressIndicator(),
                  if (controller.query.isEmpty) _history(),
                  SearchStatusPanel(controller: controller),
                ],
              ),
            ),
            if (controller.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
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
                ),
              )
            else
              _results(),
          ],
        ),
      ),
    ),
  );
  Widget _results() {
    final groups = controller.groups.values.toList(growable: false);
    return PosterGrid.builder(
      sliver: true,
      itemCount: groups.length,
      itemBuilder: (_, index) {
        final group = groups[index];
        return PosterCard(
          key: ValueKey('${group.first.sourceId}/${group.first.id}'),
          title: group.first.title,
          description: group.first.description,
          poster:
              group.where((i) => i.poster.isNotEmpty).firstOrNull?.poster ?? '',
          subtitle:
              '${group.first.year} ${group.first.remarks} · ${group.map((i) => i.sourceId).toSet().length} 个来源',
          onTap: () => _choose(group),
        );
      },
    );
  }

  Future<void> _advanced() async {
    final value = await showAdvancedSearch(context, _options);
    if (value == null || !mounted) return;
    setState(() => _options = value);
    if (text.text.trim().isNotEmpty) unawaited(_search());
  }

  Widget _searchBar() {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: EdgeInsets.all(compact ? 12 : 20),
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
                hintText: _preferredId == null ? '输入影片名称（全渠道）' : '输入影片名称',
                prefixIcon: compact ? null : const Icon(Icons.search),
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
          IconButton(
            tooltip: '高级搜索',
            icon: const Icon(Icons.tune),
            onPressed: controller.loading ? null : _advanced,
          ),
          SizedBox(width: compact ? 4 : 12),
          if (compact)
            IconButton.filled(
              tooltip: controller.loading ? '停止搜索' : '搜索',
              onPressed: controller.loading
                  ? () => setState(controller.cancel)
                  : _search,
              icon: Icon(controller.loading ? Icons.stop : Icons.search),
            )
          else
            FilledButton(
              onPressed: controller.loading
                  ? () => setState(controller.cancel)
                  : _search,
              child: Text(controller.loading ? '停止' : '搜索'),
            ),
        ],
      ),
    );
  }

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
            label: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    _inputFocus.unfocus();
    final selected = await showDialog<CatalogItem>(
      context: context,
      builder: (context) => SourceChoicesDialog(
        title: items.first.title,
        child: SingleChildScrollView(
          child: SourceChoices(
            services: widget.services,
            items: items,
            sourceNames: controller.sourceNames,
            sourceLabels: controller.sourceLabels,
            onSelected: (item) => Navigator.pop(context, item),
            onBlock: controller.blockSource,
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      context.push(
        '/detail/${selected.sourceId}/${Uri.encodeComponent(selected.id)}',
      );
    }
  }
}
