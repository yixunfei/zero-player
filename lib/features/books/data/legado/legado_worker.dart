import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:html/dom.dart' as dom;

import '../../../../core/network/cancellation_token.dart';
import '../../domain/book.dart';
import '../../domain/legado_source.dart';
import '../book_html.dart';
import 'legado_discovery.dart';
import 'legado_request.dart';
import 'legado_rule_tokens.dart';
import 'legado_rules.dart';
import 'legado_script.dart';

enum LegadoOperation {
  address,
  discovery,
  matchBookUrl,
  details,
  books,
  toc,
  content,
  articles,
  audio,
  images,
}

final class LegadoJob {
  const LegadoJob(
    this.source,
    this.uri,
    this.operation, {
    this.input = '',
    this.address = '',
    this.query = '',
    this.page = 1,
    this.discovery = false,
    this.book,
    this.chapter,
    this.documents = const {},
  });
  final BookSource source;
  final Uri uri;
  final LegadoOperation operation;
  final String input, address, query;
  final int page;
  final bool discovery;
  final Book? book;
  final BookChapter? chapter;
  final Map<String, String> documents;

  LegadoJob withDocuments(Map<String, String> values) => LegadoJob(
    source,
    uri,
    operation,
    input: input,
    address: address,
    query: query,
    page: page,
    discovery: discovery,
    book: book,
    chapter: chapter,
    documents: values,
  );
}

final class LegadoPage {
  const LegadoPage({
    this.books = const [],
    this.chapters = const [],
    this.links = const [],
    this.content = '',
    this.categories = const [],
    this.matches = false,
  });
  final List<Book> books;
  final List<BookChapter> chapters;
  final List<String> links;
  final String content;
  final List<LegadoCategory> categories;
  final bool matches;
}

Future<LegadoPage> runLegadoJob(LegadoJob job, CancellationToken token) async {
  token.check();
  final receiver = ReceivePort();
  final result = Completer<Object?>();
  void complete(Object? value) {
    if (!result.isCompleted) result.complete(value);
  }

  receiver.listen(complete);
  final unlink = token.listen(() => complete(const RequestCancelled()));
  final timer = Timer(
    const Duration(seconds: 5),
    () => complete(const FormatException('Legado 规则处理超时')),
  );
  Isolate? worker;
  try {
    worker = await Isolate.spawn(_work, (
      receiver.sendPort,
      job,
    ), onError: receiver.sendPort);
    final value = await result.future;
    token.check();
    if (value is Exception) throw value;
    if (value is LegadoPage) return value;
    throw const FormatException('Legado 规则无法解析此页面');
  } finally {
    unlink();
    timer.cancel();
    receiver.close();
    worker?.kill(priority: Isolate.immediate);
  }
}

void _work((SendPort, LegadoJob) message) {
  final (port, job) = message;
  Object result;
  try {
    result = _LegadoEvaluation(job).run();
  } on LegadoNeedsDocument catch (error) {
    result = error;
  } on FormatException catch (error) {
    result = FormatException(error.message);
  } on Object {
    result = const FormatException('Legado 规则无法解析此页面');
  }
  Isolate.exit(port, result);
}

final class _LegadoEvaluation {
  _LegadoEvaluation(this.job)
    : source = job.source,
      rules = job.source.legado!.rules,
      evaluator = LegadoRules(
        job.source,
        job.uri,
        job.input,
        key: job.query,
        page: job.page,
        book: job.book,
        chapter: job.chapter,
        documents: job.documents,
      );

  final LegadoJob job;
  final BookSource source;
  final Map<String, String> rules;
  final LegadoRules evaluator;

  LegadoPage run() => switch (job.operation) {
    LegadoOperation.address => _address(),
    LegadoOperation.discovery => LegadoPage(
      categories: legadoCategories(evaluator.elements(job.address, job.input)),
    ),
    LegadoOperation.matchBookUrl => _matchBookUrl(),
    LegadoOperation.details => _detailBook(),
    LegadoOperation.books => _books(),
    LegadoOperation.toc => _toc(),
    LegadoOperation.content => _content(),
    LegadoOperation.articles => _articles(),
    LegadoOperation.audio => _audio(),
    LegadoOperation.images => _images(),
  };

  LegadoPage _matchBookUrl() {
    final expression = RegExp(source.legado!.bookUrlPattern);
    bool matches(Uri uri) {
      final value = '$uri';
      final match = expression.matchAsPrefix(value);
      return match?.end == value.length;
    }

    return LegadoPage(
      matches:
          matches(job.uri) ||
          matches(job.uri.replace(scheme: 'http', port: 80)),
    );
  }

  LegadoPage _address() {
    if (!legadoScriptMarker.hasMatch(job.address)) {
      return LegadoPage(links: [job.address]);
    }
    final values = evaluator.elements(job.address, job.input);
    return LegadoPage(
      links: [
        for (final value in values.take(80))
          if (value is String)
            value
          else if (value is Map && value['url'] is String)
            value['url'] as String,
      ],
    );
  }

  LegadoPage _books() {
    final root = evaluator.root;
    final prefix = job.discovery && (rules['exploreList'] ?? '').isNotEmpty
        ? 'explore'
        : 'search';
    final rows = evaluator.elements(rules['${prefix}List'] ?? '', root);
    if (rows.isEmpty) return _detailBook();
    final result = <String, Book>{};
    for (final row in rows) {
      final name = bookLabel(_field('${prefix}Title', row));
      final linkRule = '${prefix}Link';
      final link = (rules[linkRule] ?? '').isEmpty
          ? job.address.isEmpty
                ? '${job.uri}'
                : job.address
          : _link(linkRule, row);
      if (name.isEmpty || link.isEmpty) continue;
      final request = _request(link);
      if (request == null) continue;
      result.putIfAbsent(
        request.targetKey,
        () => Book(
          source.id,
          source.kind,
          name,
          bookLabel(
            _optional(
              '${prefix}Author',
              row,
            ).replaceFirst(RegExp(r'^作\s*者\s*[:：]\s*'), ''),
          ),
          request.uri,
          description: bookLabel(_optional('${prefix}Description', row), 600),
          request: request.reference,
          cover: bookCoverAddress(
            job.uri,
            _optional('${prefix}Cover', row, single: true),
          ),
          category: bookLabel(_optional('${prefix}Category', row)),
          wordCount: bookLabel(_optional('${prefix}WordCount', row)),
          latestChapter: bookLabel(_optional('${prefix}Latest', row)),
          updatedLabel: bookLabel(_optional('${prefix}Updated', row)),
          rankLabel: bookLabel(_optional('${prefix}Rank', row)),
        ),
      );
    }
    return LegadoPage(
      books: result.values.toList(),
      links: job.discovery ? _links('nextExplore', root) : const [],
    );
  }

  LegadoPage _detailBook() {
    final row = _details(evaluator.root);
    final title = bookLabel(_optional('infoTitle', row));
    return LegadoPage(
      books: [
        if (title.isNotEmpty || job.book != null)
          Book(
            source.id,
            source.kind,
            title.isEmpty ? job.book!.title : title,
            bookLabel(_optional('infoAuthor', row)),
            source.requestTarget(job.uri),
            request: job.address,
            description: bookLabel(_optional('infoDescription', row), 4000),
            cover: bookCoverAddress(
              job.uri,
              _optional('infoCover', row, single: true),
            ),
            category: bookLabel(_optional('infoCategory', row)),
            wordCount: bookLabel(_optional('infoWordCount', row)),
            latestChapter: bookLabel(_optional('infoLatest', row)),
            updatedLabel: bookLabel(_optional('infoUpdated', row)),
          ),
      ],
    );
  }

  LegadoPage _toc() {
    final root = evaluator.root;
    final toc = job.page == 1
        ? _link('toc', _details(root), fallback: false)
        : '';
    final tocRequest = _request(toc);
    if (tocRequest != null &&
        (tocRequest.uri != job.uri ||
            (tocRequest.reference.isNotEmpty &&
                tocRequest.reference != job.book?.request))) {
      return LegadoPage(links: [tocRequest.targetKey]);
    }
    var selector = rules['chapters'] ?? '';
    if (selector.isEmpty &&
        job.book != null &&
        (rules['content'] ?? '').isNotEmpty) {
      final book = job.book!;
      return LegadoPage(
        chapters: [
          BookChapter(
            book.title,
            job.uri,
            request: job.uri == book.uri ? book.request : '',
          ),
        ],
      );
    }
    final reverse = selector.startsWith('-');
    if (reverse || selector.startsWith('+')) selector = selector.substring(1);
    final rows = evaluator.elements(selector, root);
    final result = <String, BookChapter>{};
    for (final row in (reverse ? rows.reversed : rows).take(4000)) {
      final title = bookLabel(_field('chapterTitle', row));
      if (title.isEmpty || _optional('chapterVolume', row) == 'true') continue;
      final media =
          source.kind == BookKind.audio && (rules['content'] ?? '').isEmpty;
      final explicit = (rules['chapterUrl'] ?? '').isNotEmpty;
      final link = _link('chapterUrl', row);
      final request = _request(
        link.isEmpty &&
                !explicit &&
                job.page == 1 &&
                rows.length == 1 &&
                row is dom.Element &&
                row.localName == 'body'
            ? job.book?.request.isNotEmpty == true
                  ? job.book!.request
                  : '${job.uri}'
            : link,
        media: media,
      );
      if (request == null) continue;
      result.putIfAbsent(
        request.targetKey,
        () => BookChapter(title, request.uri, request: request.reference),
      );
    }
    return LegadoPage(
      chapters: result.values.toList(),
      links: _links('nextToc', root),
    );
  }

  LegadoPage _articles() {
    final root = evaluator.root;
    final result = <String, BookChapter>{};
    for (final row
        in evaluator.elements(rules['articles'] ?? '', root).take(500)) {
      final title = bookLabel(_field('articleTitle', row));
      if (title.isEmpty) continue;
      final media =
          source.kind == BookKind.audio && (rules['content'] ?? '').isEmpty;
      final request = _request(_link('articleLink', row), media: media);
      if (request == null) continue;
      final description =
          (rules['content'] ?? '').isEmpty && source.kind == BookKind.text
          ? _optional('articleDescription', row, long: true)
          : '';
      result.putIfAbsent(
        request.targetKey,
        () => BookChapter(
          title,
          request.uri,
          body: description,
          request: request.reference,
        ),
      );
    }
    return LegadoPage(
      chapters: result.values.toList(),
      links: _links('nextArticles', root),
    );
  }

  LegadoPage _content() {
    final root = evaluator.root;
    final rule = rules['content'] ?? '';
    final body = evaluator.field(rule, root, long: true);
    final content = cleanLegadoContent(body, rules['replaceContent'] ?? '');
    if (content.isEmpty &&
        evaluator
            .elements(rule.replaceFirst(RegExp(r'@(?:text|html)$'), ''), root)
            .whereType<dom.Element>()
            .any(
              (node) =>
                  node.localName == 'img' || node.querySelector('img') != null,
            )) {
      throw const FormatException('章节仅提供图片，文本阅读器无法打开');
    }
    return LegadoPage(content: content, links: _links('nextContent', root));
  }

  LegadoPage _audio() {
    final link = evaluator.field(
      rules['content'] ?? '',
      evaluator.root,
      single: true,
    );
    final request = _request(link, media: true);
    return LegadoPage(links: [if (request != null) request.uri.toString()]);
  }

  LegadoPage _images() {
    final rule = rules['content'] ?? '';
    if (rule.isEmpty) return const LegadoPage();
    final addresses = <String>{};
    void add(String? value) {
      final address = value?.trim() ?? '';
      if (address.isNotEmpty && addresses.length < 100) addresses.add(address);
    }

    void addElement(dom.Element element) {
      final images = element.localName == 'img'
          ? [element]
          : element.querySelectorAll('img');
      for (final image in images) {
        add(
          image.attributes['data-src'] ??
              image.attributes['data-lazy-src'] ??
              image.attributes['data-echo'] ??
              image.attributes['data-original'] ??
              image.attributes['src'],
        );
      }
    }

    void addValue(Object? value) {
      if (value is dom.Element) {
        addElement(value);
      } else if (value is String) {
        final trimmed = value.trim();
        if (trimmed.startsWith('[')) {
          try {
            final decoded = jsonDecode(trimmed);
            if (decoded is List) {
              for (final item in decoded.take(100)) {
                if (item is String) add(item);
              }
              return;
            }
          } on FormatException {
            // Continue with HTML or a direct media address.
          }
        }
        if (trimmed.contains('<img')) {
          for (final image in parseBookHtml(trimmed).querySelectorAll('img')) {
            addElement(image);
          }
        } else {
          for (final line in trimmed.split(RegExp(r'[\r\n]+'))) {
            add(line);
          }
        }
      }
    }

    for (final value in evaluator.rawValues(rule, evaluator.root).take(100)) {
      addValue(value);
    }
    return LegadoPage(links: addresses.toList());
  }

  Object? _details(Object? root) =>
      evaluator.elements(rules['infoInit'] ?? '', root).firstOrNull ?? root;

  String _field(
    String name,
    Object? value, {
    bool long = false,
    bool single = false,
  }) => evaluator.field(rules[name] ?? '', value, long: long, single: single);

  String _optional(
    String name,
    Object? value, {
    bool long = false,
    bool single = false,
  }) {
    try {
      return _field(name, value, long: long, single: single);
    } on FormatException {
      return '';
    }
  }

  String _link(String name, Object? value, {bool fallback = true}) {
    final rule = rules[name] ?? '';
    if (rule.isNotEmpty) return evaluator.field(rule, value, single: true);
    if (!fallback) return '';
    if (value is dom.Element) return value.attributes['href'] ?? '';
    return value is String ? value : '';
  }

  List<String> _links(String name, Object? value) {
    return evaluator
        .field(rules[name] ?? '', value)
        .split('\n')
        .where((item) => item.isNotEmpty)
        .take(12)
        .toList();
  }

  LegadoRequest? _request(String value, {bool media = false}) {
    if (value.isEmpty) return null;
    try {
      return LegadoRequest.parse(
        source,
        job.uri,
        value,
        key: job.query,
        page: job.page,
        media: media,
      );
    } on FormatException {
      return null;
    }
  }
}
