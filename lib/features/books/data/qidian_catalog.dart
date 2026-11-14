import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

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
import 'qidian_saved_page.dart';

typedef QidianPage = ({
  List<Book> books,
  List<LegadoCategory> sections,
  Uri? next,
});

typedef QidianListing = ({QidianPage page, DateTime? cachedAt, bool imported});

typedef QidianInfo = ({
  String author,
  String status,
  String category,
  String latest,
  String updated,
  String words,
  String totalRecommendations,
  String weeklyRecommendations,
  String cover,
});

const qidianRecommendationId = 'qidian-discovery';
final qidianHome = Uri.https('www.qidian.com');
final _mobileHome = Uri.https('m.qidian.com');
final _workPath = RegExp(r'^/book/(\d+)/?$');
final _listingPath = RegExp(r'^/(?:mm/)?(?:all|rank|finish|free)(?:/|$)');
const _imageHosts = {'bookcover.yuewen.com', 'qidian.qpic.cn'};

/// The desktop site gates every page behind a browser fingerprint challenge
/// (HTTP 202). The mobile site serves the same catalog without it, so discovery
/// and work facts are fetched there while book links keep the desktop identity.
const _ranks = <(String, String, String)>[
  ('yuepiao', 'yuepiao', '月票榜'),
  ('hotsales', 'hotsales', '畅销榜'),
  ('readindex', 'readIndex', '阅读榜'),
  ('newfans', 'newfans', '书友榜'),
  ('rec', 'rec', '推荐榜'),
  ('update', 'update', '更新榜'),
  ('sign', 'sign', '签约榜'),
  ('newbook', 'newbook', '新书榜'),
  ('newauthor', 'newauthor', '新人榜'),
];

bool isQidianHost(String host) =>
    host == 'qidian.com' || host.endsWith('.qidian.com');

String? _csrf;
String _csrfToken() => _csrf ??= _uuid();

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
  final h = [for (var i = 0; i < 16; i++) hex(i)];
  return '${h[0]}${h[1]}${h[2]}${h[3]}-${h[4]}${h[5]}-${h[6]}${h[7]}-'
      '${h[8]}${h[9]}-${h[10]}${h[11]}${h[12]}${h[13]}${h[14]}${h[15]}';
}

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
      for (final (slug, _, title) in _ranks)
        LegadoCategory(title, '/rank/$slug/page1/', group: '男生榜单'),
      for (final (slug, _, title) in _ranks)
        LegadoCategory(title, '/mm/rank/$slug/page1/', group: '女生榜单'),
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
      page = await _loadMobile(uri, token);
    } on Exception {
      token.check();
      if (!allowed) throw const ContentBlocked();
      final cached = firstPage ? await _readCache(uri) : null;
      token.check();
      if (!allowed) throw const ContentBlocked();
      if (cached == null) rethrow;
      final filtered = _filterPage(cached.page);
      if (filtered.books.isEmpty) rethrow;
      return (
        page: filtered,
        cachedAt: cached.cachedAt,
        imported: cached.imported,
      );
    }
    token.check();
    if (!allowed) throw const ContentBlocked();
    final filtered = _filterPage(page);
    if (firstPage) await _saveCache(uri, filtered, token);
    token.check();
    if (!allowed) throw const ContentBlocked();
    return (page: _filterPage(filtered), cachedAt: null, imported: false);
  }

  Future<QidianPage> _loadMobile(Uri desktop, CancellationToken token) async {
    final target = _mobileTarget(desktop);
    final document = await _getMobile(target.uri, token);
    final input = document.text;
    if (target.homepage) {
      return Isolate.run(() => parseQidianMobileHome(input));
    }
    return Isolate.run(() => parseQidianMobileApi(desktop, input));
  }

  Future<QidianListing> importListing(
    String address,
    List<int> bytes,
    CancellationToken token, {
    required bool firstPage,
  }) async {
    final target = _pageUri(qidianHome.resolve(address));
    if (target == null) throw const FormatException('起点栏目地址无效');
    token.check();
    if (!allowed) throw const ContentBlocked();
    final page = await Isolate.run(() {
      final saved = readQidianSavedPage(bytes);
      final uri = _pageUri(saved.uri);
      if (uri == null || _listingKey(uri) != _listingKey(target)) {
        throw const FormatException('请选择当前栏目和页码对应的起点网页');
      }
      return parseQidianPage(uri, saved.text);
    });
    token.check();
    if (!allowed) throw const ContentBlocked();
    final filtered = _filterPage(page);
    if (filtered.books.isEmpty) {
      throw const FormatException('导入的网页没有可显示的作品');
    }
    final now = DateTime.now();
    if (firstPage) await _saveCache(target, filtered, token, importedAt: now);
    token.check();
    if (!allowed) throw const ContentBlocked();
    return (page: _filterPage(filtered), cachedAt: now, imported: true);
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
      final imported = raw['imported'] == true;
      final next = imported && raw['next'] is String
          ? Uri.tryParse(raw['next'] as String)
          : null;
      return (
        page: (
          books: books,
          sections: sections,
          next: next == null ? null : _pageUri(next),
        ),
        cachedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
        imported: imported,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _saveCache(
    Uri uri,
    QidianPage page,
    CancellationToken token, {
    DateTime? importedAt,
  }) async {
    final now = importedAt ?? DateTime.now();
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
              if (importedAt != null) 'imported': true,
              if (importedAt != null && page.next != null)
                'next': page.next.toString(),
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
    final id = _workPath.firstMatch(book.uri.path)![1]!;
    final document = await _getMobile(
      _mobileHome.resolve('/book/$id/'),
      token,
      work: true,
    );
    final input = document.text;
    final info = await Isolate.run(() => parseQidianInfo(input));
    return _rememberDetails(book, info, token);
  }

  Future<QidianInfo> importDetails(
    Book book,
    List<int> bytes,
    CancellationToken token,
  ) async {
    final target = _workUri(book.uri);
    token.check();
    if (!allows(book) || target == null) throw const ContentBlocked();
    final info = await Isolate.run(() {
      final saved = readQidianSavedPage(bytes);
      if (_workUri(saved.uri) != target) {
        throw const FormatException('请选择当前作品对应的起点网页');
      }
      return parseQidianInfo(saved.text);
    });
    return _rememberDetails(book, info, token);
  }

  QidianInfo _rememberDetails(
    Book book,
    QidianInfo info,
    CancellationToken token,
  ) {
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
    final uri = coverUri(book);
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

  Uri coverUri(Book book) {
    if (!allows(book)) throw const ContentBlocked();
    final uri = Uri.tryParse(book.cover);
    if (uri == null ||
        _safeUri(uri) == null ||
        !_imageHosts.contains(uri.host)) {
      throw const FormatException('起点封面域名无效');
    }
    return uri;
  }

  Future<Document> _getMobile(
    Uri uri,
    CancellationToken token, {
    bool work = false,
  }) async {
    if (!allowed) throw const ContentBlocked();
    try {
      return await network.get(
        uri,
        cancellation: token,
        networkTimeout: const Duration(seconds: 10),
        headers: {
          'Accept': 'application/json, text/html',
          'Cookie': '_csrfToken=${_csrfToken()}',
        },
        validateTarget: (target) {
          if (target.host != _mobileHome.host ||
              !(work
                  ? _workPath.hasMatch(target.path)
                  : _mobileListing(target))) {
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

bool _mobileListing(Uri uri) {
  final path = uri.path;
  return path == '/' ||
      path == '/webcommon/category/list' ||
      RegExp(r'^/webcommon/rank/[a-zA-Z]+list$').hasMatch(path);
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
    if (page.contains('{{')) continue;
    final uri = qidianHome.resolve(page);
    if (_pageUri(uri) == null) continue;
    // Only category lists translate to the mobile catalog API; desktop rank
    // slugs are replaced by the mobile rank sections added above.
    if (uri.path != '/all' && uri.path != '/mm/all') continue;
    final category =
        uri.queryParameters['chanId'] ?? rankCategory.firstMatch(uri.path)?[1];
    if (category == null) continue;
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

String _listingKey(Uri uri) {
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  final query = Map.of(uri.queryParametersAll);
  final all = RegExp(r'^(/(?:mm/)?all)(?:/([a-zA-Z0-9-]+))?$').firstMatch(path);
  if (all != null) {
    final filters = all[2]?.split('-') ?? const <String>[];
    for (final filter in filters) {
      final match = RegExp(r'^([a-zA-Z]+)(\d+)$').firstMatch(filter);
      if (match == null) return '$path?${_orderedQuery(query)}';
      final key = match[1]!;
      query[key] = [...?query[key], match[2]!];
    }
    final site = all[1] == '/mm/all' ? '0' : '1';
    if (_defaultValue(query['siteid'], site)) query.remove('siteid');
    if (_defaultValue(query['page'], '1')) query.remove('page');
    return '${all[1]}?${_orderedQuery(query)}';
  }
  final base = path.replaceFirst(RegExp(r'[/-]page1$'), '');
  return '$base?${_orderedQuery(query)}';
}

bool _defaultValue(List<String>? values, String expected) =>
    values != null && values.length == 1 && values.single == expected;

String _orderedQuery(Map<String, List<String>> query) {
  final keys = query.keys.toList()..sort();
  return Uri(queryParameters: {for (final key in keys) key: query[key]}).query;
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
  final mobile = _mobileBookInfo(input);
  if (mobile != null) return mobile;
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
    cover: _coverUrl(input),
  );
}

/// The mobile work page embeds the full catalog record (including total and
/// weekly recommendations) in its SSR page context, avoiding the desktop WAF.
QidianInfo? _mobileBookInfo(String input) {
  final data = _pageData(input);
  final info = data?['bookInfo'];
  if (info is! Map) return null;
  String text(Object? value) => bookLabel(value);
  final updated = RegExp(
    r'og:novel:update_time"\s+content="([^"]*)"',
  ).firstMatch(input)?[1];
  return (
    author: text(info['authorName']),
    status: text(info['bookStatus']).isNotEmpty
        ? text(info['bookStatus'])
        : text(info['actionStatus']),
    category: [
      text(info['chanName']),
      text(info['subCateName']),
    ].where((value) => value.isNotEmpty).join(' · '),
    latest: text(info['updChapterName']),
    updated: bookLabel(updated),
    words: text(info['showWordsCnt']),
    totalRecommendations: _count(info['recomAll']),
    weeklyRecommendations: _count(info['recomWeek']),
    cover: _coverUrl(input),
  );
}

String _count(Object? value) {
  final n = value is int ? value : int.tryParse('$value');
  if (n == null || n < 0) return '';
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(2)}亿';
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(2)}万';
  return '$n';
}

/// The work page serves the real cover under `qdbimg/349573/<bid>/…`, while the
/// discovery list only carries a low-resolution `qdbimg/3/` placeholder. Read the
/// current work's cover from its Open Graph image (or structured data / header
/// image) and request the hi-res rendition instead of the list thumbnail.
String _coverUrl(String input) {
  var raw =
      RegExp(
        r'property="og:image"\s+content="((?:https?:)?//[^"]+)"',
      ).firstMatch(input)?[1] ??
      RegExp(
        r'"image"\s*:\s*"((?:https?:)?//bookcover\.yuewen\.com/[^"]+)"',
      ).firstMatch(input)?[1];
  if (raw == null) {
    final img = RegExp(
      r'<img[^>]*class="detail__header-cover__img"[^>]*>',
    ).firstMatch(input)?.group(0);
    raw = img == null
        ? null
        : RegExp(r'(?:data-src|src)="([^"]+)"').firstMatch(img)?[1];
  }
  if (raw == null || raw.isEmpty) return '';
  final url = (raw.startsWith('//') ? 'https:$raw' : raw).replaceFirst(
    RegExp(r'/\d+$'),
    '/600',
  );
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || !_imageHosts.contains(uri.host)) {
    return '';
  }
  return uri.toString();
}

Map? _pageData(String input) {
  final marker = input.indexOf('vite-plugin-ssr_pageContext');
  if (marker < 0) return null;
  final start = input.indexOf('>', marker);
  final end = start < 0 ? -1 : input.indexOf('</script>', start + 1);
  if (start < 0 || end < 0) return null;
  try {
    final root = jsonDecode(input.substring(start + 1, end).trim());
    final context = root is Map ? root['pageContext'] : null;
    final props = context is Map ? context['pageProps'] : null;
    final data = props is Map ? props['pageData'] : null;
    return data is Map ? data : null;
  } on FormatException {
    return null;
  }
}

const _homeLists = [
  'popNovel',
  'recRank',
  'hotRank',
  'fyRank',
  'signRank',
  'newSell',
  'bestSell',
  'limitFree',
  'xqRec',
  'wxRec',
  'dzRec',
  'ljRec',
  'yjRec',
  'klRec',
  'erRec',
];

QidianPage parseQidianMobileHome(String input) {
  final data = _pageData(input);
  if (data == null) {
    throw const FormatException('起点官网未返回可识别的作品列表');
  }
  final records = <Map>[
    for (final key in _homeLists)
      if (data[key] is List) ...(data[key] as List).whereType<Map>(),
  ];
  final books = _mobileBooks(records);
  if (books.isEmpty) {
    throw const FormatException('起点官网未返回可识别的作品列表');
  }
  return (books: books, sections: const [], next: null);
}

QidianPage parseQidianMobileApi(Uri desktop, String input) {
  final Object? root;
  try {
    root = jsonDecode(input);
  } on FormatException {
    throw const FormatException('起点移动站返回了无效响应');
  }
  if (root is! Map || root['code'] != 0) {
    throw FormatException(
      '起点移动站返回错误（code ${root is Map ? root['code'] : '?'}）',
    );
  }
  final data = root['data'];
  if (data is! Map) throw const FormatException('起点移动站未返回作品列表');
  final records = (data['records'] as List? ?? const [])
      .whereType<Map>()
      .toList();
  final books = _mobileBooks(records);
  final pageNum = data['pageNum'] is int ? data['pageNum'] as int : 1;
  final pageMax = data['pageMax'] is int ? data['pageMax'] as int : 50;
  final last = data['isLast'] == 1 || data['isLast'] == true;
  final next = !last && records.isNotEmpty && pageNum < pageMax
      ? _nextDesktop(desktop, pageNum + 1)
      : null;
  return (books: books, sections: const [], next: next);
}

List<Book> _mobileBooks(List<Map> records) {
  final rows = <String, Book>{};
  for (final record in records) {
    final bid = '${record['bid'] ?? ''}';
    final title = bookLabel(record['bName']);
    if (bid.isEmpty || bid == 'null' || title.isEmpty) continue;
    final rank = record['rankNum'];
    rows.putIfAbsent(
      bid,
      () => Book(
        qidianRecommendationId,
        BookKind.text,
        title,
        bookLabel(record['bAuth']),
        qidianHome.resolve('/book/$bid/'),
        cover: 'https://bookcover.yuewen.com/qdbimg/3/$bid/180',
        description: bookLabel(record['desc'], 600),
        category: [
          bookLabel(record['cat']),
          bookLabel(record['subCat']),
        ].where((value) => value.isNotEmpty).join(' · '),
        wordCount: bookLabel(record['cnt']),
        rankLabel: rank == null ? '' : '$rank',
      ),
    );
  }
  return rows.values.toList();
}

Uri? _nextDesktop(Uri desktop, int nextPage) {
  final query = Map.of(desktop.queryParameters);
  if (query.containsKey('page')) {
    query['page'] = '$nextPage';
    return _pageUri(desktop.replace(queryParameters: query));
  }
  if (RegExp(r'page\d+').hasMatch(desktop.path)) {
    return _pageUri(
      desktop.replace(
        path: desktop.path.replaceAllMapped(
          RegExp(r'page\d+'),
          (_) => 'page$nextPage',
        ),
      ),
    );
  }
  return null;
}

({Uri uri, bool homepage}) _mobileTarget(Uri desktop) {
  final path = desktop.path;
  final query = desktop.queryParameters;
  final female =
      path.startsWith('/mm') ||
      query['siteid'] == '0' ||
      path.contains('/rank/mm/');
  final gender = female ? 'female' : 'male';
  final page =
      int.tryParse(query['page'] ?? '') ??
      int.tryParse(RegExp(r'page(\d+)').firstMatch(path)?[1] ?? '') ??
      1;
  if (path == '/' ||
      path == '/mm/' ||
      path.isEmpty ||
      path == '/finish/' ||
      path == '/free/' ||
      path == '/mm/free') {
    return (uri: _mobileHome.resolve('/'), homepage: true);
  }
  final params = {
    'gender': gender,
    'pageNum': '$page',
    '_csrfToken': _csrfToken(),
  };
  if (path.contains('/rank')) {
    final segments = path.split('/').where((part) => part.isNotEmpty).toList();
    final index = segments.indexOf('rank');
    var slug = index >= 0 && index + 1 < segments.length
        ? segments[index + 1]
        : '';
    if (slug == 'mm' && index + 2 < segments.length) slug = segments[index + 2];
    final category = RegExp(r'(?:chn|chanId)(\d+)').firstMatch(path)?[1];
    if (category != null) params['catId'] = category;
    return (
      uri: _mobileHome
          .resolve('/webcommon/rank/${_rankApi(slug)}list')
          .replace(queryParameters: params),
      homepage: false,
    );
  }
  if (query['chanId'] != null) params['catId'] = query['chanId']!;
  if (query['subCateId'] != null) params['subCatId'] = query['subCateId']!;
  return (
    uri: _mobileHome
        .resolve('/webcommon/category/list')
        .replace(queryParameters: params),
    homepage: false,
  );
}

String _rankApi(String slug) {
  const types = {
    'yuepiao': 'yuepiao',
    'hotsales': 'hotsales',
    'readindex': 'readIndex',
    'readIndex': 'readIndex',
    'newfans': 'newfans',
    'rec': 'rec',
    'recom': 'rec',
    'update': 'update',
    'sign': 'sign',
    'newbook': 'newbook',
    'newauthor': 'newauthor',
  };
  final api = types[slug];
  if (api == null) throw const FormatException('起点移动站暂不支持该榜单');
  return api;
}
