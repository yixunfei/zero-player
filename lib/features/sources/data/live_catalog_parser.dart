import '../domain/source_catalog.dart';

List<LiveCatalogEntry> parseLiveCatalog(
  Object? value,
  Uri origin,
  List<ImportDiagnostic> diagnostics,
) {
  if (value is! List) return [];
  if (value.length > 100) throw const FormatException('直播订阅超过 100 个');
  final entries = <LiveCatalogEntry>[];
  final seen = <Uri>{};
  for (final row in value.whereType<Map>()) {
    final name = '${row['name'] ?? '直播列表'}';
    final url = row['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        row['type'] == 3 ||
        row['click'] != null ||
        row['api'] != null) {
      diagnostics.add(ImportDiagnostic(name, '直播需要脚本、代理或不是 HTTP(S) 列表'));
      continue;
    }
    if (!seen.add(uri)) continue;
    final epg = Uri.tryParse('${row['epg'] ?? ''}');
    entries.add(
      LiveCatalogEntry(
        name,
        uri,
        headers: {if (row['ua'] is String) 'User-Agent': row['ua'] as String},
        epg:
            epg != null &&
                {'http', 'https'}.contains(epg.scheme) &&
                epg.host.isNotEmpty
            ? epg
            : null,
      ),
    );
  }
  return entries;
}
