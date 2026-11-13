import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../data/local_book.dart';
import '../data/public_catalog.dart';
import '../domain/book.dart';
import 'book_page_route.dart';
import 'technical_book_page.dart';

bool publicLibraryAllowed(AppServices services) =>
    !services.supervision.enabled && !services.supervision.corrupted;

String publicationField(Map<String, dynamic> row, String key) =>
    (row[key] as String? ?? '').trim();

bool publicationAllowed(AppServices services, Map<String, dynamic> row) =>
    publicLibraryAllowed(services) &&
    services.contentPolicy.textAllowed(
      '${row['title']} ${row['author']} ${row['translator'] ?? ''} ${row['category']} ${Uri.tryParse(publicationField(row, 'url'))?.host ?? ''}',
    );

class PublicationDetailPage extends StatefulWidget {
  const PublicationDetailPage({
    super.key,
    required this.services,
    required this.row,
    required this.bookRoute,
  });

  final AppServices services;
  final Map<String, dynamic> row;
  final Route<void> Function(Book book) bookRoute;

  @override
  State<PublicationDetailPage> createState() => _PublicationDetailState();
}

class _PublicationDetailState extends State<PublicationDetailPage> {
  CancellationToken? _download;
  Book? _book;
  String? _message;
  bool _launching = false;
  bool _saving = false;
  bool _opening = false;
  AppServices get _services => widget.services;
  String _field(String key) => publicationField(widget.row, key);
  bool get _allowed => publicationAllowed(_services, widget.row);
  bool get _technical => _field('source') == '书栈网';

  @override
  void initState() {
    super.initState();
    _services.contentPolicy.addListener(_policyChanged);
  }

  void _policyChanged() {
    if (!_allowed) _download?.cancel();
    setState(() {});
  }

  @override
  void dispose() {
    _download?.cancel();
    _services.contentPolicy.removeListener(_policyChanged);
    super.dispose();
  }

  Future<void> _original() async {
    if (!_allowed || _launching) return;
    setState(() => _launching = true);
    try {
      final uri = publicBookUri(Uri.parse(_field('url')));
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException('没有可打开原站的应用');
      }
    } on Exception {
      if (mounted) setState(() => _message = '无法打开原站，请检查浏览器后重试');
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _readTechnical() async {
    if (!_allowed || _opening) return;
    _opening = true;
    try {
      final uri = publicBookUri(Uri.parse(_field('url')));
      await Navigator.of(context).push(
        BookPageRoute<void>(
          builder: (_) => TechnicalBookPage(
            services: _services,
            uri: uri,
            title: _field('title'),
          ),
        ),
      );
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      _opening = false;
    }
  }

  Future<void> _downloadAndOpen() async {
    if (!_allowed || _download != null || _opening) return;
    if (_book case final book?) {
      await _openBook(book);
      return;
    }
    final token = CancellationToken();
    setState(() {
      _download = token;
      _message = '正在下载 EPUB…';
    });
    Book? imported;
    try {
      imported = await _import(token);
      if (mounted) {
        setState(() {
          _book = imported;
          _message = '已添加到书架';
        });
      }
    } on Exception {
      if (mounted) {
        setState(
          () => _message = token.isCancelled ? '下载已取消' : '暂时无法导入此版本，可打开原站获取文件',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _download = null;
        });
      }
    }
    if (mounted && _allowed && !token.isCancelled && imported != null) {
      await _openBook(imported);
    }
  }

  Future<void> _openBook(Book book) async {
    _opening = true;
    try {
      final entry = await _services.books.store.entry(book);
      if (!mounted || !_allowed) return;
      if (entry == null) {
        setState(() {
          _book = null;
          _message = '已从书架移除，可重新下载';
        });
        return;
      }
      await Navigator.of(context).push(widget.bookRoute(book));
    } on Exception {
      if (mounted) setState(() => _message = '无法打开书架记录，请重试');
    } finally {
      _opening = false;
    }
  }

  Future<Book> _import(CancellationToken token) async {
    final repo = _services.books;
    final address = publicBookUri(Uri.parse(_field('download')));
    final data = await repo.client.network.get(
      address,
      cancellation: token,
      maxBytes: maxLocalBookBytes,
      validateTarget: (target) {
        publicBookUri(target);
        if (target.host != 'www.gutenberg.org') {
          throw const FormatException('下载地址不在出版渠道范围');
        }
      },
    );
    token.check();
    if (!mounted || !_allowed) throw const RequestCancelled();
    setState(() {
      _saving = true;
      _message = '正在导入书架…';
    });
    await repo.documents.create(recursive: true);
    final staging = await repo.documents.createTemp('.publication-');
    final label = _field(
      'title',
    ).replaceAll(RegExp(r'[^\p{L}\p{N} ._-]', unicode: true), '').trim();
    final filename = label.isEmpty ? 'publication' : bookLabel(label, 80);
    final file = File(p.join(staging.path, '$filename.epub'));
    try {
      await file.writeAsBytes(data.bytes, flush: true);
      token.check();
      return await repo.importLocal(
        file,
        catalogMetadata: {
          for (final field in widget.row.entries)
            if (field.value is String) field.key: field.value as String,
        },
      );
    } finally {
      try {
        if (await file.exists()) await file.delete();
        await staging.delete();
      } on FileSystemException {
        // A temporary file cleanup failure cannot undo a successful import.
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('书目详情')),
    body: !_allowed
        ? const Center(child: Text('当前内容策略限制访问此作品'))
        : SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    SelectableText(
                      _field('title'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (_field('author').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SelectableText(_field('author')),
                      ),
                    const SizedBox(height: 16),
                    _actions(),
                    if (_message case final message?)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(message, semanticsLabel: message),
                      ),
                    if (_download != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                    const Divider(height: 32),
                    _metadata('来源', _field('source')),
                    _metadata(
                      '语种',
                      publicationLanguageLabel(_field('language')),
                    ),
                    _metadata('版本', _field('version')),
                    _metadata('译者／贡献者', _field('translator')),
                    _metadata('许可', _field('license')),
                    _metadata(
                      '主题',
                      _field('category').replaceAll('Category: ', ''),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );

  Widget _actions() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (_technical)
        FilledButton.icon(
          onPressed: _readTechnical,
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('应用内阅读'),
        ),
      if (_field('download').isNotEmpty)
        FilledButton.icon(
          onPressed: _download == null ? _downloadAndOpen : null,
          icon: Icon(
            _book == null ? Icons.download_outlined : Icons.menu_book_outlined,
          ),
          label: Text(_book == null ? '下载 EPUB 并阅读' : '打开书架中的电子书'),
        ),
      OutlinedButton.icon(
        onPressed: _launching ? null : _original,
        icon: const Icon(Icons.open_in_new),
        label: Text(_field('source') == '好读二代' ? '前往原站领取' : '打开原站'),
      ),
      if (_download != null && !_saving)
        TextButton(onPressed: _download!.cancel, child: const Text('取消下载')),
    ],
  );

  Widget _metadata(String label, String text) => text.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 3),
              SelectableText(text),
            ],
          ),
        );
}
