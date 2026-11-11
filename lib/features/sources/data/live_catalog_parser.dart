import 'dart:convert';
import 'dart:io';

import '../../../core/network/header_policy.dart';
import '../../../core/network/network_target_policy.dart';
import '../domain/source_catalog.dart';
import 'catalog_url.dart';

List<LiveCatalogEntry> parseLiveCatalog(
  Object? value,
  Uri origin,
  List<ImportDiagnostic> diagnostics,
) {
  if (value is! List) return [];
  if (value.length > 100) throw const FormatException('直播订阅超过 100 个');
  final entries = <LiveCatalogEntry>[];
  final seen = <Uri>{};

  void add(Map row, String name, Uri? uri) {
    if (uri == null ||
        uri.host == 'local-import.invalid' ||
        row['api'] != null ||
        row['click'] != null ||
        (row['type'] != null && !{'0', '1', '2'}.contains('${row['type']}'))) {
      diagnostics.add(ImportDiagnostic(name, '直播需要脚本、代理或不是 HTTP(S) 列表'));
      return;
    }
    if (!seen.add(uri)) return;
    final guide = row['epg'];
    final headers = row['header'] ?? row['headers'];
    entries.add(
      LiveCatalogEntry(
        name,
        uri,
        headers: HeaderPolicy.sanitize({
          if (headers is Map)
            for (final e in headers.entries)
              if (e.key is String &&
                  e.value is String &&
                  {
                    'user-agent',
                    'referer',
                    'origin',
                  }.contains((e.key as String).toLowerCase()))
                e.key as String: e.value as String,
          if (row['ua'] is String) 'User-Agent': row['ua'] as String,
        }),
        // TVBox per-channel/date templates aren't XMLTV documents.
        epg: guide is String && !guide.contains(RegExp(r'[{}]'))
            ? resolveCatalogUrl(guide, origin)
            : null,
      ),
    );
  }

  var redirects = 0;
  for (final row in value.whereType<Map>()) {
    if (row['group'] == 'redirect' &&
        row['channels'] is List &&
        row['api'] == null &&
        row['click'] == null) {
      for (final child in (row['channels'] as List).whereType<Map>()) {
        final urls = child['urls'];
        if (urls is! List) continue;
        for (final url in urls.whereType<String>()) {
          if (++redirects > 100) throw const FormatException('直播跳转超过 100 个');
          add(child, '${child['name'] ?? '直播列表'}', _redirect(url));
        }
      }
    } else {
      final uri = resolveCatalogUrl(row['url'], origin);
      final address = uri == null ? null : InternetAddress.tryParse(uri.host);
      add(
        row,
        '${row['name'] ?? '直播列表'}',
        // Loopback URLs in TVBox configs point at its internal proxy server.
        address?.isLoopback == true && uri!.path.startsWith('/proxy')
            ? null
            : uri,
      );
    }
  }
  if (entries.length > 100) throw const FormatException('直播订阅超过 100 个');
  return entries;
}

Uri? _redirect(String url) {
  // This legacy form is a data pointer. Only unwrap a literal public list.
  const prefix = 'proxy://do=live&type=txt&ext=';
  if (!url.startsWith(prefix)) return null;
  final target = url.substring(prefix.length);
  try {
    final text = target.startsWith(RegExp(r'https?://', caseSensitive: false))
        ? target
        : utf8.decode(base64.decode(target));
    final uri = parseCatalogUrl(text);
    const NetworkTargetPolicy().validateAccess(uri, originalOrigin: false);
    return uri;
  } on FormatException {
    return null;
  }
}
