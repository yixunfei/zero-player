import 'dart:convert';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/text/display_text.dart';

typedef MusicCatalogPage<T> = ({List<T> items, int? next, int? total});
typedef MusicCatalogOption = ({String id, String name, String group});

const musicCatalogPlatforms = {
  'neteasePlaylist': '网易云音乐',
  'qqPlaylist': 'QQ 音乐',
  'kugouPlaylist': '酷狗音乐',
};

final musicCatalogId = RegExp(r'^[1-9][0-9]{0,19}$');

List<dynamic> musicCatalogRows(Object? raw) {
  if (raw is! List) throw const FormatException('平台目录数据格式已变更');
  return raw;
}

Map musicCatalogObject(Object? raw, [int? code]) {
  if (raw is! Map || (code != null && raw['code'] != code)) {
    throw const FormatException('平台目录暂不可用');
  }
  return raw;
}

String musicCatalogLabel(Object? value) =>
    value is String && value.length <= 1000 ? displayText(value) : '';

int? musicCatalogCount(Object? value) {
  final count = int.tryParse('$value');
  return count != null && count >= 0 ? count : null;
}

int? musicCatalogNext(int offset, int count, int size, int? total) =>
    count == 0 || (total == null ? count < size : offset + count >= total)
    ? null
    : offset + count;

final class MusicCatalogApi {
  MusicCatalogApi(
    this.network, {
    Uri? netease,
    Uri? qq,
    Uri? kugou,
    Uri? kugouWeb,
    this.timeout = const Duration(seconds: 12),
  }) : netease = netease ?? Uri.https('music.163.com'),
       qq = qq ?? Uri.https('u.y.qq.com'),
       kugou = kugou ?? Uri.https('pc.service.kugou.com'),
       kugouWeb = kugouWeb ?? Uri.https('www.kugou.com');

  final DocumentClient network;
  final Uri netease, qq, kugou, kugouWeb;
  final Duration timeout;

  Future<Document> get(Uri uri, CancellationToken token) => network.get(
    uri,
    headers: uri.origin == qq.origin
        ? const {'Referer': 'https://y.qq.com/'}
        : const {},
    cancellation: token,
    networkTimeout: timeout,
    maxBytes: 4 * 1024 * 1024,
  );

  Future<Map> qqRequest(
    String module,
    String method,
    Map<String, Object?> params,
    CancellationToken token,
  ) async {
    final uri = qq
        .resolve('/cgi-bin/musicu.fcg')
        .replace(
          queryParameters: {
            'data': jsonEncode({
              'comm': {'ct': 24},
              'req': {'module': module, 'method': method, 'param': params},
            }),
          },
        );
    final raw = musicCatalogObject((await get(uri, token)).json, 0);
    return musicCatalogObject(musicCatalogObject(raw['req'], 0)['data']);
  }

  /// One round trip for several QQ modules; the site batches them the same way.
  Future<List<Map>> qqBatch(
    List<({String module, String method, Map<String, Object?> params})> requests,
    CancellationToken token,
  ) async {
    if (requests.isEmpty) return [];
    final uri = qq
        .resolve('/cgi-bin/musicu.fcg')
        .replace(
          queryParameters: {
            'data': jsonEncode({
              'comm': {'ct': 24},
              for (var i = 0; i < requests.length; i++)
                'req_$i': {
                  'module': requests[i].module,
                  'method': requests[i].method,
                  'param': requests[i].params,
                },
            }),
          },
        );
    final raw = musicCatalogObject((await get(uri, token)).json, 0);
    return [
      for (var i = 0; i < requests.length; i++)
        musicCatalogObject(musicCatalogObject(raw['req_$i'], 0)['data']),
    ];
  }
}
