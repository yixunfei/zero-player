import 'dart:convert';

import '../domain/source_catalog.dart';
import 'jsonc_decoder.dart';
import 'live_catalog_parser.dart';

/// Classifies a single document. Fetching, user selection and recursion budgets
/// belong to the subscription use case, never to this pure parser.
final class JsonSourceCatalogParser implements SourceCatalogParser {
  const JsonSourceCatalogParser({
    this.maxBytes = 2 * 1024 * 1024,
    this.maxEntries = 500,
    this.maxReferences = 50,
  });
  final int maxBytes;
  final int maxEntries;
  final int maxReferences;

  @override
  SourceCatalog parse(String input, Uri origin) {
    if (utf8.encode(input).length > maxBytes) {
      throw const FormatException('Configuration exceeds byte limit');
    }
    final decoded = decodeJsonc(input.replaceFirst('\uFEFF', ''));
    final sources = <SourceCandidate>[];
    final references = <CatalogReference>[];
    final diagnostics = <ImportDiagnostic>[];
    final seen = <String>{};
    if (decoded is Map && decoded['urls'] is List) {
      _references(decoded['urls'] as List, origin, references, diagnostics);
    }
    final List rows;
    final bool tvbox;
    if (decoded is List) {
      rows = decoded;
      tvbox = false;
    } else if (decoded is Map && decoded['sites'] is List) {
      rows = decoded['sites'] as List;
      tvbox = true;
    } else if (decoded is Map && decoded['sources'] is List) {
      rows = decoded['sources'] as List;
      tvbox = false;
    } else if (decoded is Map &&
        (decoded['urls'] is List || decoded['lives'] is List)) {
      rows = [];
      tvbox = false;
    } else {
      throw const FormatException('Unrecognized source configuration');
    }
    if (rows.length > maxEntries) {
      throw const FormatException('Too many source entries');
    }
    for (final row in rows) {
      _source(row, origin, tvbox, sources, diagnostics, seen);
    }
    final lives = decoded is Map
        ? parseLiveCatalog(decoded['lives'], origin, diagnostics)
        : <LiveCatalogEntry>[];
    return SourceCatalog(
      sources: sources,
      references: references,
      diagnostics: diagnostics,
      lives: lives,
    );
  }

  void _source(
    Object? row,
    Uri origin,
    bool tvbox,
    List<SourceCandidate> sources,
    List<ImportDiagnostic> diagnostics,
    Set<String> seen,
  ) {
    if (row is! Map) {
      diagnostics.add(const ImportDiagnostic('', '条目不是对象'));
      return;
    }
    final name = (row['name'] ?? row['key'] ?? '未命名源').toString();
    if (tvbox && row['type'] != 1) {
      diagnostics.add(ImportDiagnostic(name, '未支持的 TVBox 类型（Spider/XML/未知）'));
      return;
    }
    final value = tvbox
        ? row['api']
        : row['baseUrl'] ?? row['url'] ?? row['api'];
    final uri = _url(value, origin);
    if (uri == null ||
        uri.path.endsWith('.js') ||
        uri.path.endsWith('.jar') ||
        uri.path.endsWith('.py') ||
        uri.queryParameters.containsKey('url')) {
      diagnostics.add(ImportDiagnostic(name, '不是支持的直连接口'));
      return;
    }
    if (!seen.add(uri.toString())) {
      diagnostics.add(ImportDiagnostic(name, '重复地址'));
      return;
    }
    sources.add(
      SourceCandidate(
        name: name,
        endpoint: uri,
        kind: !tvbox && row['kind'] == 'kanju'
            ? SourceKind.kanju
            : !tvbox && row['kind'] == 'macCmsHtml'
            ? SourceKind.macCmsHtml
            : SourceKind.cms,
        requestedEnabled: row['enabled'] == true,
      ),
    );
  }

  void _references(
    List rows,
    Uri origin,
    List<CatalogReference> references,
    List<ImportDiagnostic> diagnostics,
  ) {
    if (rows.length > maxReferences) {
      throw const FormatException('Too many child catalogs');
    }
    final seen = <Uri>{};
    for (final row in rows) {
      if (row is! Map) {
        diagnostics.add(const ImportDiagnostic('', '子仓不是对象'));
        continue;
      }
      final uri = _url(row['url'], origin);
      final name = (row['name'] ?? '未命名子仓').toString();
      if (uri == null || uri == origin || !seen.add(uri)) {
        diagnostics.add(ImportDiagnostic(name, '无效、重复或自引用的子仓'));
      } else {
        references.add(CatalogReference(name, uri));
      }
    }
  }

  Uri? _url(Object? value, Uri origin) {
    if (value is! String || value.trim().isEmpty) return null;
    if (value.startsWith('csp_') ||
        value.startsWith('js:') ||
        value.startsWith('py:')) {
      return null;
    }
    Uri uri;
    try {
      uri = origin.resolve(value.trim());
    } on FormatException {
      return null;
    }
    if (!{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }
}
