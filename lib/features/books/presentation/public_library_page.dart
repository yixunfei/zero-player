import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../data/public_catalog.dart';
import '../domain/book.dart';
import 'book_page_route.dart';
import 'publication_detail_page.dart';

class PublicLibraryPage extends StatefulWidget {
  const PublicLibraryPage({
    super.key,
    required this.services,
    required this.bookRoute,
  });

  final AppServices services;
  final Route<void> Function(Book book) bookRoute;

  @override
  State<PublicLibraryPage> createState() => _PublicLibraryState();
}

class _PublicLibraryState extends State<PublicLibraryPage> {
  static const _batchSize = 60;
  final _scroll = ScrollController(keepScrollOffset: false);
  final _search = TextEditingController();
  Map<PublicationCollection, List<Map<String, dynamic>>>? _catalog;
  List<Map<String, dynamic>> _visible = [];
  PublicationCollection _collection = PublicationCollection.literature;
  PublicationLanguage? _language;
  String? _source;
  String _field = '全部';
  String _query = '';
  int _limit = _batchSize;
  Timer? _typing;
  bool _failed = false;
  bool _opening = false;
  bool get _allowed => publicLibraryAllowed(widget.services);

  @override
  void initState() {
    super.initState();
    widget.services.contentPolicy.addListener(_policyChanged);
    if (_allowed) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final rows = await PublicCatalog.load();
      if (!mounted) return;
      final sections = {
        for (final collection in PublicationCollection.values)
          collection: <Map<String, dynamic>>[],
      };
      for (final row in rows) {
        sections[PublicationCollection.forBook(row)]!.add(row);
      }
      final technical = sections[PublicationCollection.technical]!;
      sections[PublicationCollection.technical] = [
        for (final source in PublicationCollection.technical.sources)
          ...technical.where((row) => row['source'] == source),
      ];
      setState(() {
        _catalog = sections;
        _filter();
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _policyChanged() {
    if (_allowed && _catalog == null && !_failed) unawaited(_load());
    setState(_filter);
  }

  void _filter() {
    _visible = !_allowed
        ? []
        : (_catalog?[_collection] ?? const <Map<String, dynamic>>[])
              .where(
                (row) =>
                    (_source == null || row['source'] == _source) &&
                    (_language?.matches(publicationField(row, 'language')) ??
                        true) &&
                    publicationMatches(row, _query, _field) &&
                    publicationAllowed(widget.services, row),
              )
              .take(_limit + 1)
              .toList();
  }

  void _changeFilter(VoidCallback change) {
    _typing?.cancel();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      change();
      _query = _search.text.trim();
      _limit = _batchSize;
      _filter();
    });
  }

  Future<void> _showPublication(Map<String, dynamic> row) async {
    if (_opening || !publicationAllowed(widget.services, row)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _opening = true;
    try {
      await Navigator.of(context).push(
        BookPageRoute<void>(
          builder: (_) => PublicationDetailPage(
            services: widget.services,
            row: row,
            bookRoute: widget.bookRoute,
          ),
        ),
      );
    } finally {
      _opening = false;
    }
  }

  @override
  void dispose() {
    widget.services.contentPolicy.removeListener(_policyChanged);
    _typing?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('出版书目')),
    body: !_allowed
        ? const Center(child: Text('当前监管策略限制访问出版书目'))
        : _failed
        ? Center(
            child: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('书目载入失败，重试'),
            ),
          )
        : _catalog == null
        ? const Center(child: CircularProgressIndicator())
        : Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: _browse(),
            ),
          ),
  );

  Widget _browse() => CustomScrollView(
    controller: _scroll,
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    slivers: [
      SliverToBoxAdapter(child: _filters()),
      if (_visible.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('没有符合条件的图书')),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          sliver: SliverList.builder(
            itemCount: _visible.length,
            itemBuilder: (_, index) {
              if (index == _limit) {
                return Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _limit += _batchSize;
                      _filter();
                    }),
                    child: const Text('加载更多'),
                  ),
                );
              }
              return _tile(_visible[index]);
            },
          ),
        ),
      SliverToBoxAdapter(
        child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
      ),
    ],
  );

  Widget _filters() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final collection in PublicationCollection.values)
              ChoiceChip(
                label: Text(collection.label),
                selected: collection == _collection,
                onSelected: (_) {
                  if (collection == _collection) return;
                  _changeFilter(() {
                    _collection = collection;
                    _source = null;
                    _language = null;
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          maxLength: 120,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: '搜索书名或作者',
            counterText: '',
            isDense: true,
            suffixIcon: IconButton(
              tooltip: '清空书目搜索',
              icon: const Icon(Icons.clear),
              onPressed: () => _changeFilter(_search.clear),
            ),
          ),
          onChanged: (_) {
            _typing?.cancel();
            _typing = Timer(
              const Duration(milliseconds: 230),
              () => _changeFilter(() {}),
            );
          },
          onSubmitted: (_) => _changeFilter(() {}),
        ),
        const SizedBox(height: 4),
        _filterChoices(),
      ],
    ),
  );

  Widget _filterChoices() => Wrap(
    spacing: 16,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      DropdownButton<String>(
        value: _field,
        items: const [
          DropdownMenuItem(value: '全部', child: Text('全部字段')),
          DropdownMenuItem(value: '书名', child: Text('仅书名')),
          DropdownMenuItem(value: '作者', child: Text('仅作者')),
        ],
        onChanged: (value) => _changeFilter(() => _field = value!),
      ),
      if (_collection.sources.length > 1)
        DropdownButton<String>(
          value: _source ?? '',
          items: [
            const DropdownMenuItem(value: '', child: Text('全部来源')),
            for (final source in _collection.sources)
              DropdownMenuItem(value: source, child: Text(source)),
          ],
          onChanged: (value) =>
              _changeFilter(() => _source = value == '' ? null : value),
        ),
      DropdownButton<String>(
        value: _language?.name ?? '',
        items: [
          const DropdownMenuItem(value: '', child: Text('全部语种')),
          for (final language in PublicationLanguage.values)
            DropdownMenuItem(value: language.name, child: Text(language.label)),
        ],
        onChanged: (value) => _changeFilter(
          () => _language = value == ''
              ? null
              : PublicationLanguage.values.byName(value!),
        ),
      ),
    ],
  );

  Widget _tile(Map<String, dynamic> row) {
    final source = publicationField(row, 'source');
    final technical = _collection == PublicationCollection.technical;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(technical ? Icons.code : Icons.menu_book_outlined),
        title: Text(
          publicationField(row, 'title'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            publicationField(row, 'author'),
            source,
            publicationLanguageLabel(publicationField(row, 'language')),
          ].where((text) => text.isNotEmpty).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showPublication(row),
      ),
    );
  }
}
