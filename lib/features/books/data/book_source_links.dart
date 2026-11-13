import 'package:html/parser.dart' as html;

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../sources/domain/video_source.dart';
import '../domain/book.dart';

const maxBookSourceBytes = 64 * 1024 * 1024;

final _repositoryPage = RegExp(
  r'^/yuedu/(shuyuan|shuyuans|rss|rsss)/content/id/(\d+)\.html$',
);
final _repositoryDownload = RegExp(
  r'^/yuedu/(shuyuan|shuyuans|rss|rsss)/json/id/\d+\.json$',
);
final _repositoryRelease = RegExp(
  r'^/gh/mumuceo/file\d+(?:@[\w.-]+)?/[\w/.-]+\.json$',
);
const _cdn = {'cdn.jsdelivr.net', 'gcore.jsdelivr.net', 'fastly.jsdelivr.net'};

Uri bookSourceLink(String input) {
  var uri = Uri.parse(input.trim());
  if (uri.scheme == 'legado' || uri.scheme == 'yuedu') {
    final route = '${uri.host}${uri.path}'.toLowerCase();
    if (!const {
      'import/booksource',
      'import/rsssource',
      'booksource/importonline',
      'rsssource/importonline',
    }.contains(route)) {
      throw const FormatException('此链接不是 Legado 书源或订阅源导入链接');
    }
    final raw =
        uri.query.startsWith('src=http://') ||
            uri.query.startsWith('src=https://')
        ? uri.query.substring(4)
        : uri.queryParameters['src'];
    if (raw == null || raw.isEmpty) throw const FormatException('导入链接缺少来源地址');
    uri = Uri.parse(raw);
  }
  uri = legacyBookUri(uri);
  final parts = uri.pathSegments;
  if (uri.host == 'github.com' &&
      parts.length >= 5 &&
      {'blob', 'raw'}.contains(parts[2])) {
    return Uri(
      scheme: 'https',
      host: 'raw.githubusercontent.com',
      pathSegments: [...parts.take(2), ...parts.skip(3)],
    );
  }
  return _releaseMirror(uri);
}

String bookSubscriptionId(Uri uri) {
  final page = uri.host == 'www.yckceo.com'
      ? _repositoryPage.firstMatch(uri.path)
      : null;
  final canonical = page == null
      ? uri
      : uri.replace(path: '/yuedu/${page[1]}/json/id/${page[2]}.json');
  return stableId('book-subscription:$canonical');
}

Uri _releaseMirror(Uri uri) =>
    _cdn.contains(uri.host) &&
        _repositoryRelease.hasMatch(uri.path) &&
        !uri.pathSegments.any((part) => part == '..' || part == '.')
    ? uri.replace(host: 'fastly.jsdelivr.net')
    : uri;

final class BookSourceDocuments {
  const BookSourceDocuments(this.network, this.hostAllowed);
  final DocumentClient network;
  final bool Function(String) hostAllowed;

  Future<String> load(Uri origin, CancellationToken token) async {
    var target = origin;
    if (origin.host == 'www.yckceo.com' &&
        _repositoryPage.hasMatch(origin.path)) {
      final page = await _fetch(origin, token, maxBytes: 4 * 1024 * 1024);
      final link = html
          .parse(page.text)
          .querySelector('input#jsonurl')
          ?.attributes['value'];
      if (link == null || link.trim().isEmpty) {
        throw const FormatException('详情页没有公开的来源下载链接');
      }
      target = publicBookUri(page.uri.resolve(link.trim()));
      if (target.host != origin.host ||
          !_repositoryDownload.hasMatch(target.path)) {
        throw const FormatException('详情页返回了无效的来源下载地址');
      }
    }
    return (await _fetch(target, token, maxBytes: maxBookSourceBytes)).text;
  }

  Future<Document> _fetch(
    Uri origin,
    CancellationToken token, {
    required int maxBytes,
  }) {
    return network.get(
      origin,
      maxBytes: maxBytes,
      cancellation: token,
      networkTimeout: const Duration(seconds: 60),
      mapRedirect: (target) => _releaseMirror(publicBookUri(target)),
      validateTarget: (target) {
        publicBookUri(target);
        if (!hostAllowed(target.host) || !_allowed(origin, target)) {
          throw const FormatException('来源文件跳转超出允许范围');
        }
      },
    );
  }

  bool _allowed(Uri origin, Uri target) {
    if (origin.host == target.host) return true;
    if (origin.host == 'www.yckceo.com' &&
        _repositoryDownload.hasMatch(origin.path) &&
        target.host == 'fastly.jsdelivr.net' &&
        _repositoryRelease.hasMatch(target.path)) {
      return true;
    }
    final parts = origin.pathSegments;
    return origin.host == 'github.com' &&
        parts.length >= 6 &&
        parts[2] == 'releases' &&
        parts[3] == 'download' &&
        {
          'release-assets.githubusercontent.com',
          'objects.githubusercontent.com',
        }.contains(target.host) &&
        target.path.startsWith('/github-production-release-asset');
  }
}
