import 'dart:convert';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../supervision/domain/content_classification.dart';
import '../domain/source_identity.dart';
import 'catalog_url.dart';

const awesomeZhuijuRepository =
    'https://github.com/laoma528/awesome-zhuiju-free';
const awesomeZhuijuSubscription = '$awesomeZhuijuRepository#zero-player-manual';
const awesomeZhuijuBuiltin = '$awesomeZhuijuRepository#zero-player-builtin';

enum AwesomeResourceKind { website, catalog }

final class AwesomeResource {
  const AwesomeResource(this.name, this.uri, this.kind);
  final String name;
  final Uri uri;
  final AwesomeResourceKind kind;
}

final class AwesomeZhuijuIndex {
  const AwesomeZhuijuIndex(
    this.checkedAt,
    this.candidates,
    this.blocked,
    this.skipped,
  );
  final DateTime checkedAt;
  final List<AwesomeResource> candidates;
  final Set<String> blocked;
  final int skipped;

  static String identity(Uri uri) => sourceEndpointIdentity('catalog', uri);

  static String videoIdentity(String kind, Uri uri) {
    if (kind != 'cms') return sourceIdentity(kind, uri);
    final host = uri.host.endsWith('.bfzyapi.com') ? 'bfzyapi.com' : uri.host;
    final path = uri.path.replaceFirstMapped(
      RegExp(r'(/api[.]php/provide/vod)(?:/(?:from|at)/[^/]+)+/?$'),
      (match) => match[1]!,
    );
    final query = Map<String, List<String>>.of(uri.queryParametersAll);
    for (final key in ['ac', 'pg', 'wd', 'ids', 't']) {
      query.remove(key);
    }
    // The root Creative Video API already covers its source selector variants.
    if (host == 'ys.cxkjg.cn' && path == '/api/provide/vod') {
      query.remove('source');
    }
    return sourceIdentity(
      kind,
      uri.replace(
        scheme: 'https',
        host: host,
        path: path,
        queryParameters: query.isEmpty ? null : query,
        query: query.isEmpty ? '' : null,
      ),
    );
  }

  static bool durable(Uri uri) => !uri.queryParameters.keys.any(
    RegExp(r'token|sign|auth|expire|deadline', caseSensitive: false).hasMatch,
  );

  static Future<AwesomeZhuijuIndex> download(
    DocumentClient network,
    CancellationToken token,
  ) async {
    const api =
        'https://api.github.com/repos/laoma528/awesome-zhuiju-free/contents';
    Future<Object?> read(String path) async {
      final document = await network.get(
        Uri.parse('$api/$path?ref=main'),
        headers: const {
          'User-Agent': 'Zero-Player',
          'Accept': 'application/vnd.github+json',
        },
        maxBytes: 1024 * 1024,
        cancellation: token,
        networkTimeout: const Duration(seconds: 12),
      );
      final body = document.json;
      if (body is! Map ||
          body['encoding'] != 'base64' ||
          body['content'] is! String) {
        throw const FormatException('GitHub 源目录响应格式无效');
      }
      return jsonDecode(
        utf8.decode(
          base64.decode(
            (body['content'] as String).replaceAll(RegExp(r'\s'), ''),
          ),
        ),
      );
    }

    final documents = await Future.wait([
      read('resources/resources.json'),
      read('reports/availability.json'),
    ]);
    return parse(documents[0], documents[1]);
  }

  static AwesomeZhuijuIndex parse(Object? catalog, Object? report) {
    if (catalog is! Map ||
        catalog['version'] != 1 ||
        catalog['resources'] is! List ||
        report is! Map ||
        report['version'] != 1 ||
        report['results'] is! List) {
      throw const FormatException('awesome-zhuiju-free 目录格式未识别');
    }
    final checkedAt = DateTime.tryParse('${report['generated_at']}');
    final resources = catalog['resources'] as List;
    final results = report['results'] as List;
    if (checkedAt == null ||
        resources.length > 2000 ||
        results.length > 2000 ||
        resources.isEmpty ||
        results.isEmpty) {
      throw const FormatException('上游检测报告缺少可核对的数据');
    }
    final reachable = <(String, String)>{};
    final blocked = <String>{};
    for (final row in results.whereType<Map>()) {
      final uri = _uri(row['url']);
      if (uri == null || row['resource_id'] is! String) continue;
      final key = identity(uri);
      if (row['status'] == 'reachable') {
        reachable.add((row['resource_id'] as String, key));
      } else {
        blocked.add(key);
      }
    }

    final entries = <AwesomeResource>[];
    var skipped = 0;
    for (final row in resources.whereType<Map>()) {
      final kind = switch (row['category']) {
        'online_video' => AwesomeResourceKind.website,
        'tvbox_config' ||
        'subscription' ||
        'iptv' => AwesomeResourceKind.catalog,
        _ => null,
      };
      if (kind == null) continue;
      final uri = _uri(row['url']);
      final name = row['name'];
      if (uri == null || name is! String || row['id'] is! String) {
        skipped++;
        continue;
      }
      final key = identity(uri);
      final verification = row['verification'];
      final access = row['access'];
      final tags = row['tags'] is List ? (row['tags'] as List).join(' ') : '';
      final adult =
          name.startsWith('伦理') ||
          adultContent('$name ${row['summary'] ?? ''} $tags', category: true);
      if (adult ||
          verification is Map &&
              {
                'removed',
                'unavailable',
                'unreachable',
              }.contains(verification['status'])) {
        blocked.add(key);
      }
      if (blocked.contains(key) ||
          !reachable.contains((row['id'] as String, key)) ||
          (access is Map && access['requires_login'] == true)) {
        skipped++;
        continue;
      }
      entries.add(AwesomeResource(name, uri, kind));
    }
    final allowed = entries
        .where((r) => !blocked.contains(identity(r.uri)))
        .toList();
    return AwesomeZhuijuIndex(
      checkedAt,
      allowed,
      blocked,
      skipped + entries.length - allowed.length,
    );
  }

  static Uri? _uri(Object? value) {
    if (value is! String) return null;
    try {
      return parseCatalogUrl(value);
    } on FormatException {
      return null;
    }
  }
}
