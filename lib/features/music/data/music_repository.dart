import '../../../core/network/cancellation_token.dart';
import '../../sources/domain/video_source.dart';
import '../../supervision/application/content_policy.dart';
import '../../supervision/domain/supervision_rules.dart';
import '../domain/music_track.dart';
import 'music_parser.dart';
import 'myfreemp3_client.dart';
import 'public_music_sources.dart';
import 'website_music_sources.dart';

final class MusicRepository {
  MusicRepository(this.client, {this.policy});
  final MyFreeMp3Client client;
  final ContentPolicy? policy;
  late final public = PublicMusicSources(client.network);
  VideoSource sourceFor(String provider) => provider == 'myfreemp3'
      ? source
      : VideoSource(
          id: 'music-$provider',
          name: musicSources[provider] ?? provider,
          kind: 'music',
          enabled: true,
          endpoint: Uri.parse(switch (provider) {
            'audius' => 'https://audius.co',
            'archive' => 'https://archive.org',
            'lxHuibq' => 'https://lxmusicapi.onrender.com',
            'qqmp3' => 'https://www.qqmp3.vip',
            'musicBox' => 'https://mu-jie.cc/musicBox/',
            'lxHuanyin' => 'https://music-dl.sayqz.com',
            'lxQdy' || 'lxXinghai' => 'https://music-api.gdstudio.xyz',
            'lxExclusive' => 'https://88.lxmusic.xn--fiqs8s',
            'lxHelloWorld' => 'https://c.wwwweb.top',
            'lxHyw' => 'https://103.79.184.97',
            'lxFlower' || 'lxGrass' => 'http://97.64.37.235',
            'lxJuhe' => 'https://api.music.lerd.dpdns.org',
            _ => 'https://music.163.com',
          }),
        );
  Map<String, String> headers(MusicTrack track) => track.provider == 'myfreemp3'
      ? const {'Referer': 'https://myfreemp3.ink/'}
      : {'qqmp3', 'musicBox'}.contains(track.provider)
      ? WebsiteMusicSources.headers(track.provider)
      : const {};
  static final source = VideoSource(
    id: 'music-myfreemp3',
    name: 'MY FREE MP3',
    kind: 'music',
    enabled: true,
    endpoint: Uri.parse('https://myfreemp3.ink'),
  );

  bool allowed(MusicTrack track) =>
      musicSources.containsKey(track.provider) &&
      !(track.explicit && (policy?.filterAdult ?? true)) &&
      (policy?.sourceAllowed(sourceFor(track.provider)) ?? true) &&
      (policy?.textAllowed('${track.title} ${track.artist}') ?? true);

  Future<MusicSearchResult> search(
    String query, {
    int page = 1,
    CancellationToken? cancellation,
    String provider = 'myfreemp3',
  }) async {
    query = query
        .replaceAll(RegExp(r'[\\/\x00-\x1f\x7f?#%<>{}\[\]|^`]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (query.isEmpty || query.length > 100 || page < 1 || page > 1000) {
      throw const FormatException('请输入 1–100 字的歌名或歌手');
    }
    if (!musicSources.containsKey(provider)) {
      throw const FormatException('未知音乐渠道');
    }
    policy?.requireSource(sourceFor(provider));
    if (!(policy?.textAllowed(query) ?? true)) throw const ContentBlocked();
    if (provider != 'myfreemp3') {
      final result = await public.search(provider, query, page, cancellation);
      return MusicSearchResult(
        List.unmodifiable(result.tracks.where(allowed)),
        hasNext: result.hasNext,
      );
    }
    final document = await client.search(
      query,
      page,
      cancellation: cancellation,
    );
    cancellation?.check();
    policy?.requireSource(source);
    final result = parseMusicSearch(document.text, query: query, page: page);
    return MusicSearchResult(
      List.unmodifiable(result.tracks.where(allowed)),
      hasNext: result.hasNext,
    );
  }

  Future<MusicTrack> resolve(
    MusicTrack track,
    CancellationToken cancellation, {
    bool refresh = false,
  }) async {
    if (!allowed(track)) throw const ContentBlocked();
    if (track.provider != 'myfreemp3') {
      return public.resolve(track, cancellation);
    }
    if (!refresh &&
        DateTime.now().difference(track.fetchedAt) <
            const Duration(minutes: 10)) {
      return track;
    }
    final result = await search(
      track.query.isEmpty ? '${track.artist} ${track.title}' : track.query,
      page: track.page,
      cancellation: cancellation,
    );
    return result.tracks.where((item) => item.id == track.id).firstOrNull ??
        (throw const FormatException('歌曲地址已失效，请重新搜索后播放'));
  }
}
