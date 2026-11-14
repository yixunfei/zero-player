import 'dart:convert';
import 'dart:isolate';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/persistence/app_database.dart';
import '../../supervision/application/content_policy.dart';
import '../../supervision/domain/supervision_rules.dart';
import '../domain/book.dart';
import '../domain/legado_source.dart';
import 'aoaostar_book_catalog.dart';

typedef QidianPage = ({
  List<Book> books,
  List<LegadoCategory> sections,
  Uri? next,
});

typedef QidianListing = ({QidianPage page, DateTime? cachedAt});

typedef QidianInfo = ({
  String author,
  String status,
  String category,
  String latest,
  String updated,
  String words,
  String totalRecommendations,
  String weeklyRecommendations,
});

const qidianRecommendationId = 'qidian-discovery';
final qidianHome = Uri.https('www.qidian.com');
final _workPath = RegExp(r'^/book/(\d+)/?$');
final _listingPath = RegExp(r'^/(?:mm/)?(?:all|rank|finish|free)(?:/|$)');
const _imageHosts = {'bookcover.yuewen.com', 'qidian.qpic.cn'};

bool isQidianHost(String host) =>
    host == 'qidian.com' || host.endsWith('.qidian.com');

final class QidianCatalog {
  QidianCatalog(this.network, this.policy, this.db);
  final DocumentClient network;
  final ContentPolicy policy;
  final AppDatabase db;
  late final Future<List<LegadoCategory>> sections = _bundledSections();
  final _details = <String, (DateTime, QidianInfo)>{};

  bool get allowed =>
      !policy.supervision.enabled &&
      !policy.supervision.corrupted &&
      policy.textAllowed('起点中文网 www.qidian.com');

  bool allows(Book book) =>
      allowed &&
      policy.textAllowed(
        '${book.title} ${book.author} ${book.description} ${book.latestChapter}',
        category: book.category,
      );

  Future<List<LegadoCategory>> _bundledSections() async {
    final base = [
      const LegadoCategory('精选推荐', '/', group: '起点中文网'),
      const LegadoCategory('全部作品', '/all/', group: '起点中文网'),
      const LegadoCategory('女频全部作品', '/mm/all/', group: '起点中文网'),
      const LegadoCategory('完本', '/finish/', group: '起点中文网'),
      const LegadoCategory('免费', '/free/', group: '起点中文网'),
      const LegadoCategory('主站排行', '/rank/', group: '官网榜单'),
      const LegadoCategory('女频排行', '/mm/rank/', group: '官网榜单'),
      const LegadoCategory('追读榜', '/rank/followReading/', group: '官网榜单'),
      const LegadoCategory('留存榜', '/rank/retention/', group: '官网榜单'),
      const LegadoCategory('潜力榜', '/rank/potential/', group: '官网榜单'),
      const LegadoCategory('签约新书榜', '/rank/signNewBkAll/', group: '官网榜单'),
    ];
    try {
      final pack = await AoaoStarBookCatalog.load();
      final imported = await pack.read(packId: '71e56d4f');
      final source = imported.sources.firstWhere((s) => s.name == '起点中文');
      return [...base, ..._groupSections(source.legado!.categories)];
    } on Exception {
      return base;
    }
  }

  Future<QidianListing> load(
    String address,
    CancellationToken token, {
    bool firstPage = true,
  }) async {
    final uri = _pageUri(qidianHome.resolve(address));
    if (uri == null) throw const FormatException('起点栏目地址无效');
    if (!allowed) throw const ContentBlocked();
    QidianPage page;
    try {
      final document = await _get(uri, token);
      final origin = document.uri;
      final body = document.text;
      page = await Isolate.run(() => parseQidianPage(origin, body));
    } on Exception {
      token.check();
      if (!allowed) throw const ContentBlocked();
      final cached = firstPage ? await _readCache(uri) : null;
      token.check();
      if (!allowed) throw const ContentBlocked();
      if (cached == null) rethrow;
      final filtered = _filterPage(cached.page);
      if (filtered.books.isEmpty) rethrow;
      return (page: filtered, cachedAt: cached.cachedAt);
    }
    token.check();
    if (!allowed) throw const ContentBlocked();
    final filtered = _filterPage(page);
    if (firstPage) await _saveCache(uri, filtered, token);
    token.check();
    if (!allowed) throw const ContentBlocked();
    return (page: _filterPage(filtered), cachedAt: null);
  }

  QidianPage _filterPage(QidianPage page) {
    return (
      books: page.books.where(allows).toList(),
      sections: page.sections
          .where((item) => policy.textAllowed(item.title))
          .toList(),
      next: page.next,
    );
  }

  static const _cachePrefix = 'qidian:';
  static const _cacheAge = Duration(days: 7);

  Future<QidianListing?> _readCache(Uri uri) async {
    try {
      final rows = await db.rows(
        'SELECT payload,updated_at FROM recommendation_cache WHERE provider=? AND updated_at>=?',
        [
          '$_cachePrefix$uri',
          DateTime.now().subtract(_cacheAge).millisecondsSinceEpoch,
        ],
      );
      final row = rows.firstOrNull;
      if (row == null) return null;
      final raw = jsonDecode(row['payload'] as String) as Map;
      final books = (raw['books'] as List)
          .take(200)
          .whereType<Map>()
          .map(Book.fromJson)
          .where(
            (book) =>
                book.sourceId == qidianRecommendationId &&
                book.kind == BookKind.text &&
                book.request.isEmpty &&
                book.title.isNotEmpty &&
                _workUri(book.uri) == book.uri,
          )
          .toList();
      final sections = LegadoSource.readCategories(raw['sections'])
          .where(
            (section) => _pageUri(qidianHome.resolve(section.address)) != null,
          )
          .toList();
      return (
        page: (books: books, sections: sections, next: null),
        cachedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _saveCache(
    Uri uri,
    QidianPage page,
    CancellationToken token,
  ) async {
    final now = DateTime.now();
    try {
      await db.transaction(() async {
        token.check();
        if (!allowed) return;
        final key = '$_cachePrefix$uri';
        if (page.books.isEmpty) {
          await db.customStatement(
            'DELETE FROM recommendation_cache WHERE provider=?',
            [key],
          );
          return;
        }
        await db.customStatement(
          'INSERT OR REPLACE INTO recommendation_cache VALUES(?,?,?)',
          [
            key,
            jsonEncode({
              'books': page.books
                  .take(200)
                  .map((book) => book.toJson())
                  .toList(),
              'sections': page.sections
                  .take(512)
                  .map((section) => section.toJson())
                  .toList(),
            }),
            now.millisecondsSinceEpoch,
          ],
        );
        await db.customStatement(
          "DELETE FROM recommendation_cache WHERE provider GLOB 'qidian:*' AND "
          "(updated_at < ? OR provider NOT IN (SELECT provider FROM recommendation_cache "
          "WHERE provider GLOB 'qidian:*' ORDER BY updated_at DESC LIMIT 24))",
          [now.subtract(_cacheAge).millisecondsSinceEpoch],
        );
      });
    } on Exception {
      token.check();
    }
  }

  Future<QidianInfo> details(Book book, CancellationToken token) async {
    if (!allows(book) || _workUri(book.uri) == null) {
      throw const ContentBlocked();
    }
    token.check();
    final cached = _details[book.id];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 15)) {
      _requireDetails(cached.$2);
      return cached.$2;
    }
    final document = await _get(book.uri, token);
    final input = document.text;
    final info = await Isolate.run(() => parseQidianInfo(input));
    token.check();
    if (!allows(book)) throw const ContentBlocked();
    _requireDetails(info);
    if (_details.length >= 128) _details.remove(_details.keys.first);
    _details[book.id] = (DateTime.now(), info);
    return info;
  }

  void _requireDetails(QidianInfo info) {
    if (!policy.textAllowed(
      '${info.author} ${info.latest}',
      category: info.category,
    )) {
      throw const ContentBlocked();
    }
  }

  Future<List<int>> cover(Book book, CancellationToken token) async {
    if (!allows(book)) throw const ContentBlocked();
    final uri = Uri.tryParse(book.cover);
    if (uri == null ||
        _safeUri(uri) == null ||
        !_imageHosts.contains(uri.host)) {
      throw const FormatException('起点封面域名无效');
    }
    final document = await network.get(
      uri,
      cancellation: token,
      maxBytes: 1024 * 1024,
      validateTarget: (target) {
        publicBookUri(target);
        if (!_imageHosts.contains(target.host)) {
          throw const FormatException('起点封面域名无效');
        }
      },
    );
    token.check();
    if (!allows(book)) throw const ContentBlocked();
    return document.bytes;
  }

  Future<Document> _get(Uri uri, CancellationToken token) async {
    if (!allowed) throw const ContentBlocked();
    final listing = _pageUri(uri) != null;
    try {
      return await network.get(
        uri,
        cancellation: token,
        networkTimeout: const Duration(seconds: 10),
        headers: const {'Accept': 'text/html,application/xhtml+xml'},
        validateTarget: (target) {
          if ((listing ? _pageUri(target) : _workUri(target)) == null) {
            throw const FormatException('起点页面地址无效');
          }
        },
      );
    } on RemoteFailure catch (error) {
      if (error.status == 202 || error.status == 403) {
        throw FormatException('起点官网要求浏览器验证（HTTP ${error.status}）');
      }
      rethrow;
    }
  }
}

Iterable<LegadoCategory> _groupSections(List<LegadoCategory> sections) sync* {
  final parents = <(String, String), String>{};
  for (final item in sections) {
    final uri = Uri.tryParse(item.address.replaceAll('{{page}}', '1'));
    final category = uri?.queryParameters['chanId'];
    if (category != null && uri?.queryParameters['subCateId'] == null) {
      parents[(item.group, category)] = item.title;
    }
  }
  final rankCategory = RegExp(r'(?:chn|chanId)(\d+)');
  for (final item in sections) {
    final page = item.address.replaceAll('{{page}}', '1');
    if (page.contains('{{') || _pageUri(qidianHome.resolve(page)) == null) {
      continue;
    }
    final uri = Uri.parse(page);
    final category =
        uri.queryParameters['chanId'] ?? rankCategory.firstMatch(uri.path)?[1];
    final parent = parents[(item.group, category)];
    yield LegadoCategory(
      item.title,
      page,
      group: [
        item.group,
        ?parent,
      ].where((value) => value.isNotEmpty).join(' · '),
    );
  }
}

Uri? _pageUri(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  if (uri.host != qidianHome.host ||
      (path != '/' && path != '/mm/' && !_listingPath.hasMatch(path))) {
    return null;
  }
  return _safeUri(uri.replace(path: path));
}

Uri? _workUri(Uri uri) {
  final id = _workPath.firstMatch(uri.path)?[1];
  if (id == null || uri.host != qidianHome.host || _safeUri(uri) == null) {
    return null;
  }
  return qidianHome.resolve('/book/$id/');
}

Uri? _safeUri(Uri uri) {
  try {
    return publicBookUri(uri);
  } on FormatException {
    return null;
  }
}

Uri? _link(Uri base, String? value) {
  if (value == null || value.isEmpty || value.startsWith('#')) return null;
  final reference = Uri.tryParse(value);
  if (reference == null) return null;
  final uri = base.resolveUri(reference);
  return uri.scheme == 'http' && uri.port == 80
      ? uri.replace(scheme: 'https', port: 443)
      : uri;
}

dom.Document _document(String input) {
  final doc = html.parse(input);
  if (doc.querySelector('script[src*="/probe.js"]') != null ||
      (doc.querySelector('title')?.text.contains('WAF拦截') ?? false)) {
    throw const FormatException('起点官网要求浏览器验证');
  }
  for (final node in doc.querySelectorAll(
    'script,style,iframe,template,noscript,svg,[hidden]',
  )) {
    node.remove();
  }
  return doc;
}

QidianPage parseQidianPage(Uri uri, String input) {
  final doc = _document(input);
  final path = uri.path;
  final overview = const {
    '',
    '/',
    '/mm/',
    '/rank/',
    '/mm/rank/',
  }.contains(path);
  final books = _works(doc, uri, overview);
  final sections = _sections(doc, uri);
  if (books.isEmpty &&
      doc.querySelector('.book-img-text,.no-data,.no-result') == null &&
      !(overview && sections.isNotEmpty)) {
    throw const FormatException('起点官网未返回可识别的作品列表');
  }
  Uri? next;
  final element = doc.querySelector(
    'a.lbf-pagination-next:not(.lbf-pagination-disabled), a[rel="next"]',
  );
  final target = _link(uri, element?.attributes['href']);
  if (target != null) next = _pageUri(target);
  if (element != null && (next == null || next == _pageUri(uri))) {
    final current = doc.querySelector('.lbf-pagination-current');
    final number = int.tryParse(current?.text.trim() ?? '');
    if (number != null) {
      final sibling = doc
          .querySelectorAll('.lbf-pagination-page')
          .where((a) => a.text.trim() == '${number + 1}')
          .firstOrNull;
      final page = _link(uri, sibling?.attributes['href']);
      if (page != null) next = _pageUri(page);
    }
  }
  return (
    books: books,
    sections: sections,
    next: next == _pageUri(uri) ? null : next,
  );
}

List<Book> _works(dom.Document doc, Uri base, bool overview) {
  final rows = <Uri, Book>{};
  final covers = <Uri, Uri>{};
  for (final image in doc.querySelectorAll('a[href*="/book/"] img')) {
    final address = _link(base, image.parent?.attributes['href']);
    final uri = address == null ? null : _workUri(address);
    final cover = _link(
      base,
      image.attributes['data-src'] ?? image.attributes['src'],
    );
    if (uri != null &&
        cover != null &&
        _imageHosts.contains(cover.host) &&
        _safeUri(cover) != null) {
      covers[uri] = cover;
    }
  }
  for (final link in doc.querySelectorAll(
    overview
        ? 'a[href*="/book/"]'
        : '.book-mid-info h2 a, .book-img-text h2 a, .rank-view-list h2 a',
  )) {
    final address = _link(base, link.attributes['href']);
    final uri = address == null ? null : _workUri(address);
    if (uri == null) continue;
    final row = link.parent?.parent;
    final title = bookLabel(
      link.text.isNotEmpty ? link.text : link.attributes['title'],
    );
    if (title.isEmpty ||
        const {'书籍详情', '立即阅读', '免费阅读', '加入书架'}.contains(title)) {
      continue;
    }
    final image =
        row?.parent?.querySelector('.book-img-box img') ??
        link.querySelector('img');
    final cover =
        covers[uri] ??
        _link(base, image?.attributes['data-src'] ?? image?.attributes['src']);
    rows.putIfAbsent(
      uri,
      () => Book(
        qidianRecommendationId,
        BookKind.text,
        title,
        _text(row, '.author .name'),
        uri,
        cover:
            cover != null &&
                _imageHosts.contains(cover.host) &&
                _safeUri(cover) != null
            ? '$cover'
            : '',
        description: bookLabel(row?.querySelector('.intro')?.text, 600),
        category: [
          _text(row, '.author a:not(.name):not(.go-sub-type)'),
          _text(row, '.author .go-sub-type'),
        ].where((label) => label.isNotEmpty).join(' · '),
        latestChapter: _text(row, '.update a'),
        rankLabel: base.path.contains('/rank/') ? _rankLabel(row?.parent) : '',
      ),
    );
  }
  return rows.values.toList();
}

String _rankLabel(dom.Element? row) {
  final text = _text(
    row,
    '.rank-tag, .rank-no, .book-img-box .rank, .book-img-box [data-rank]',
  );
  final value = RegExp(
    r'^(?:NO\.?\s*)?(\d+)$',
    caseSensitive: false,
  ).firstMatch(text);
  return value?[1] ?? '';
}

List<LegadoCategory> _sections(dom.Document doc, Uri base) {
  final entries = <(String, Uri), LegadoCategory>{};
  for (final link in doc.querySelectorAll('a[href]')) {
    final target = _link(base, link.attributes['href']);
    if (target == null || _pageUri(target) == null) continue;
    final title = bookLabel(link.text);
    if (title.isEmpty ||
        title.startsWith('更多') ||
        title.length > 24 ||
        !RegExp(r'[\u3400-\u9fff]').hasMatch(title)) {
      continue;
    }
    final path = target.path;
    final isRank =
        path.contains('/rank/') &&
        path.split('/').where((part) => part.isNotEmpty).lastOrNull != 'rank';
    final category =
        RegExp(r'(?:/|-)(chanId|subCateId)\d+').hasMatch(path) ||
        target.queryParameters.containsKey('chanId');
    if (!isRank && !category) continue;
    final group = isRank
        ? '官网榜单'
        : link.classes.contains('go-sub-type')
        ? '官网子分类'
        : '官网分类';
    entries.putIfAbsent((
      group,
      target,
    ), () => LegadoCategory(title, '$target', group: group));
  }
  return entries.values.toList();
}

String _text(dom.Element? node, String selector) =>
    bookLabel(node?.querySelector(selector)?.text);

QidianInfo parseQidianInfo(String input) {
  final doc = _document(input);
  String meta(String key) => bookLabel(
    doc.querySelector('meta[property="og:novel:$key"]')?.attributes['content'],
  );
  final main =
      doc.querySelector('.book-info, .book-detail-info, .book-information') ??
      doc.body;
  final stats = main?.text ?? '';
  String count(String label) {
    final match = RegExp(
      '([0-9][0-9,.]*(?:\\s*[万亿])?)\\s*$label',
    ).firstMatch(stats);
    if (match == null) return '';
    // Do not treat a readable suffix of an obfuscated number as the count.
    final prefix = stats.substring(0, match.start).runes.lastOrNull;
    if (prefix != null &&
        (prefix > 0xffff ||
            (prefix >= 0xe000 && prefix <= 0xf8ff) ||
            prefix == 0x2e ||
            prefix == 0x2c)) {
      return '';
    }
    return match[1]!.trim();
  }

  final author = meta('author');
  final status = meta('status');
  final category = meta('category');
  final latest = meta('latest_chapter_name');
  final updated = meta('update_time');
  if (meta('book_name').isEmpty && main?.querySelector('h1') == null) {
    throw const FormatException('起点官网未返回可识别的作品信息');
  }
  return (
    author: author.isNotEmpty ? author : _text(main, 'h1 a, .writer'),
    status: status.isNotEmpty
        ? status
        : _text(main, '.tag .blue, .book-status'),
    category: category.isNotEmpty
        ? category
        : _text(main, '.tag a, .book-category'),
    latest: latest.isNotEmpty
        ? latest
        : _text(main, '.update a, .latest-chapter a'),
    updated: updated,
    words: count('(?:总字数|字)'),
    totalRecommendations: count('总推荐'),
    weeklyRecommendations: count('周推荐'),
  );
}
