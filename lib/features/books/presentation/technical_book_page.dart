import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../domain/book.dart';

/// Static HTML only. Every resource uses the same constrained network client.
class TechnicalBookPage extends StatefulWidget {
  const TechnicalBookPage({
    super.key,
    required this.services,
    required this.uri,
    required this.title,
  });
  final AppServices services;
  final Uri uri;
  final String title;
  @override
  State<TechnicalBookPage> createState() => _TechnicalBookState();
}

class _TechnicalBookState extends State<TechnicalBookPage> {
  CancellationToken? _token;
  late Uri _retryUri = widget.uri;
  List<({String title, Uri uri})> _chapters = [];
  String? _body, _error;
  bool _busy = true;
  bool get _allowed =>
      !widget.services.supervision.enabled &&
      !widget.services.supervision.corrupted &&
      widget.services.contentPolicy.textAllowed(
        '${widget.title} ${widget.uri.host}',
      );
  @override
  void initState() {
    super.initState();
    widget.services.contentPolicy.addListener(_blocked);
    _load(widget.uri);
  }

  void _blocked() {
    _token?.cancel();
    _token = null;
    setState(() {
      _chapters = [];
      _body = null;
      _busy = false;
      _retryUri = widget.uri;
      _error = '内容策略已变更';
    });
  }

  Future<Document> _fetch(Uri uri, CancellationToken token) =>
      widget.services.books.client.network.get(
        uri,
        cancellation: token,
        maxBytes: 8 * 1024 * 1024,
        validateTarget: (target) {
          publicBookUri(target);
          if (target.host != widget.uri.host &&
              target.host != 'static.bookstack.cn') {
            throw const FormatException('技术书资源不在声明站点');
          }
        },
      );

  Future<void> _load(Uri uri) async {
    _token?.cancel();
    final token = _token = CancellationToken();
    setState(() {
      _retryUri = uri;
      _body = null;
      _busy = true;
      _error = null;
    });
    try {
      if (!_allowed) throw const FormatException('当前监管策略限制访问');
      final data = await _fetch(uri, token);
      token.check();
      final doc = html.parse(data.text);
      _readContents(doc);
      if (_chapters.isEmpty) throw const FormatException('原站未返回可用目录');
      if (uri == widget.uri) return;
      final body =
          doc.querySelector('#page-content') ??
          doc.querySelector('.book-content, .article-content, .markdown-body');
      if (body == null) throw const FormatException('原站未返回章节正文');
      for (final n in body.querySelectorAll(
        'script,iframe,object,embed,style,link,video,audio,svg,form',
      )) {
        n.remove();
      }
      final captions = body
          .querySelectorAll('img[alt]')
          .map((e) => e.attributes['alt']);
      if (body.text.trim().isEmpty && body.querySelector('img') == null) {
        throw const FormatException('原站未返回章节正文');
      }
      if (!widget.services.contentPolicy.textAllowed(
        '${body.text} ${captions.join(' ')}',
      )) {
        throw const FormatException('正文受内容策略限制');
      }
      final images = _prepareImages(body);
      if (!mounted || !_allowed || token.isCancelled) return;
      setState(() {
        _body = body.innerHtml;
        _busy = false;
      });
      await _inlineImages(body, images, data.uri, token);
    } on Exception catch (error) {
      if (mounted && !token.isCancelled) {
        setState(
          () => _error = switch (error) {
            RemoteFailure(:final message) ||
            FormatException(:final message) => message,
            _ => '目录或正文暂不可用',
          },
        );
      }
    } finally {
      if (mounted && identical(_token, token)) setState(() => _busy = false);
    }
  }

  void _readContents(dom.Document doc) {
    final prefix = '/read/${widget.uri.pathSegments.last}/';
    final seen = <String>{};
    final chapters = <({String title, Uri uri})>[];
    for (final link in doc.querySelectorAll('a[href]')) {
      final href = link.attributes['href']!;
      final title = link.text.trim();
      if (href.startsWith(prefix) &&
          title.isNotEmpty &&
          widget.services.contentPolicy.textAllowed(title) &&
          seen.add(href)) {
        chapters.add((title: title, uri: widget.uri.resolve(href)));
      }
    }
    if (chapters.length > _chapters.length) _chapters = chapters;
  }

  List<({dom.Element element, String source})> _prepareImages(
    dom.Element body,
  ) {
    final images = <({dom.Element element, String source})>[];
    for (final element in body.querySelectorAll('*')) {
      element.attributes.removeWhere(
        (key, _) =>
            key.toString().startsWith('on') ||
            const {'style', 'srcset', 'href', 'background'}.contains(key),
      );
      if (element.localName != 'img') continue;
      final fallback = element.attributes.remove('src');
      final original = element.attributes.remove('data-original');
      final lazy = element.attributes.remove('data-src');
      final src = original ?? lazy ?? fallback;
      if (src != null) images.add((element: element, source: src));
    }
    return images;
  }

  Future<void> _inlineImages(
    dom.Element body,
    List<({dom.Element element, String source})> images,
    Uri base,
    CancellationToken token,
  ) async {
    final remaining = images.iterator;
    Future<void> load() async {
      while (!token.isCancelled && remaining.moveNext()) {
        final image = remaining.current;
        final src = await _imageData(base, image.source, token);
        if (!mounted || !_allowed || token.isCancelled) return;
        if (src != null) {
          image.element.attributes['src'] = src;
          setState(() => _body = body.innerHtml);
        }
      }
    }

    await Future.wait([load(), load()]);
  }

  Future<String?> _imageData(
    Uri base,
    String src,
    CancellationToken token,
  ) async {
    try {
      final picture = await _fetch(base.resolve(src), token);
      final type = picture.contentType?.split(';').first;
      if (const {
        'image/png',
        'image/jpeg',
        'image/webp',
        'image/gif',
      }.contains(type)) {
        return 'data:$type;base64,${base64Encode(picture.bytes)}';
      }
    } on Exception {
      // The chapter remains readable when an illustration cannot be retrieved.
    }
    return null;
  }

  void _showContents() {
    _token?.cancel();
    _token = null;
    setState(() {
      _body = _error = null;
      _busy = false;
    });
  }

  @override
  void dispose() {
    _token?.cancel();
    widget.services.contentPolicy.removeListener(_blocked);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_allowed ? widget.title : '技术图书'),
      actions: [
        IconButton(
          tooltip: '章节目录',
          onPressed: _allowed && _chapters.isNotEmpty ? _showContents : null,
          icon: const Icon(Icons.list),
        ),
      ],
    ),
    body: _busy
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: TextButton(
              onPressed: _allowed ? () => _load(_retryUri) : null,
              child: Text(_allowed ? '$_error，重试' : _error!),
            ),
          )
        : _body == null
        ? ListView.builder(
            itemCount: _chapters.length,
            itemBuilder: (context, index) {
              final chapter = _chapters[index];
              return ListTile(
                title: Text(chapter.title),
                onTap: () => _load(chapter.uri),
              );
            },
          )
        : SingleChildScrollView(
            key: ValueKey(_retryUri),
            padding: const EdgeInsets.all(20),
            child: SelectionArea(
              child: HtmlWidget(
                _body!,
                onTapUrl: (_) => true,
                textStyle: const TextStyle(fontSize: 18, height: 1.7),
              ),
            ),
          ),
  );
}
