import 'dart:convert';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/network_target_policy.dart';
import '../domain/music_track.dart';

const lxNativeNames = {
  'lxHuibq': 'Huibq',
  'lxHuanyin': '幻音',
  'lxQdy': 'QDY',
  'lxXinghai': '星海',
  'lxIkun': 'IKUN',
  'lxExclusive': '独家公共接口',
  'lxHelloWorld': 'Hello World',
  'lxHyw': 'HYW 公益版',
  'lxFlower': '野花',
  'lxGrass': '野草',
  'lxJuhe': '聚合 API',
};

final class LxNativeSources {
  LxNativeSources(this.network, {this.endpoint});
  final DocumentClient network;
  final Uri? endpoint;
  Uri _uri(String value) {
    final uri = Uri.parse(value);
    return endpoint?.replace(path: uri.path, query: uri.query) ?? uri;
  }

  Future<MusicTrack> resolve(MusicTrack track, CancellationToken token) async {
    if (!RegExp(r'^\d+$').hasMatch(track.id)) {
      throw const FormatException('LX 网易云歌曲标识无效');
    }
    if (track.provider == 'lxIkun') {
      throw const FormatException('IKUN 当前脚本未提供公开密钥，不能免授权使用');
    }
    if (track.provider == 'lxHuanyin') {
      return track.withUrl(
        Uri.https('music-dl.sayqz.com', '/api/', {
          'source': 'netease',
          'id': track.id,
          'type': 'url',
          'br': '128k',
        }),
      );
    }
    if (track.provider == 'lxHelloWorld' || track.provider == 'lxJuhe') {
      return _post(track, token);
    }
    if (track.provider == 'lxFlower' || track.provider == 'lxGrass') {
      return _plant(track, token);
    }
    final uri = switch (track.provider) {
      'lxHuibq' => Uri.https(
        'lxmusicapi.onrender.com',
        '/url/wy/${track.id}/128k',
      ),
      'lxExclusive' => Uri.https(
        '88.lxmusic.xn--fiqs8s',
        '/lxmusicv4/url/wy/${track.id}/128k',
      ),
      'lxQdy' || 'lxXinghai' => Uri.https(
        'music-api.gdstudio.xyz',
        '/api.php',
        {'types': 'url', 'source': 'netease', 'id': track.id, 'br': '128'},
      ),
      'lxHyw' => Uri.https('103.79.184.97', '/api/music/url', {
        'platform': 'wy',
        'source': 'wy',
        'songId': track.id,
        'quality': '128k',
        'key': '6C1F-53W0-GRKI-EVFG',
      }),
      _ => throw const FormatException('此 LX 音源尚未完成原生协议适配'),
    };
    final doc = await network.get(
      _uri(uri.toString()),
      cancellation: token,
      headers: {
        'User-Agent': 'LX-Music-Mobile',
        if (track.provider == 'lxHuibq') 'X-Request-Key': 'share-v3',
        if (track.provider == 'lxExclusive') 'X-Request-Key': 'lxmusic',
        if (track.provider == 'lxHyw') 'X-Card-Key': '6C1F-53W0-GRKI-EVFG',
      },
    );
    return _result(track, doc.json);
  }

  Future<MusicTrack> _post(MusicTrack track, CancellationToken token) async {
    final hello = track.provider == 'lxHelloWorld';
    final doc = await network.postJson(
      _uri(
        hello
            ? 'https://c.wwwweb.top/music/url'
            : 'https://api.music.lerd.dpdns.org/wy',
      ),
      hello
          ? {'source': 'wy', 'musicId': track.id, 'quality': '128k'}
          : {
              'type': '128k',
              'musicInfo': {
                'songmid': track.id,
                'name': track.title,
                'singer': track.artist,
              },
            },
      headers: {'User-Agent': 'lx-music-desktop/2.10.1'},
      cancellation: token,
    );
    // A 303 body can contain executable request instructions. Only the fixed
    // direct-URL response is supported by the native adapter.
    return _result(track, doc.json);
  }

  Future<MusicTrack> _plant(MusicTrack track, CancellationToken token) async {
    final flower = track.provider == 'lxFlower';
    final path = '/url/${flower ? 'wy' : 'kw'}/${track.id}/128k';
    final parts = RegExp(
      r'(?:\d\w)+',
    ).allMatches(path).map((m) => m[0]!).toList();
    final payload = flower
        ? const JsonEncoder.withIndent(' ').convert(parts)
        : jsonEncode(parts);
    final tag = utf8
        .encode(payload)
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    final doc = await network.get(
      _uri('http://97.64.37.235/${flower ? 'flower' : 'grass'}/v1$path'),
      headers: {
        'User-Agent': 'lx-music-desktop/2.10.1',
        'ver': '2.10.1',
        'source-ver': '1',
        'tag': tag,
      },
      cancellation: token,
    );
    return _result(track, doc.json);
  }

  MusicTrack _result(MusicTrack track, Object? raw) {
    if (raw is! Map || (raw['code'] != null && raw['code'] != 200)) {
      throw const FormatException('LX 接口暂不支持此请求，请更换渠道');
    }
    final data = raw;
    final nested = data['data'];
    final value =
        data['url'] ??
        (nested is Map
            ? nested['url']
            : nested is String
            ? nested
            : null);
    if (value is! String || value.isEmpty) {
      throw const FormatException('LX 接口没有返回可用地址，请更换渠道');
    }
    final url = Uri.parse(value);
    NetworkTargetPolicy.validateUri(url);
    return track.withUrl(url);
  }
}
