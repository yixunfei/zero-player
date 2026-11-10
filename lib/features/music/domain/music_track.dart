const musicPlaylistProviders = {
  'neteasePlaylist': '网易云歌单',
  'qqPlaylist': 'QQ 音乐歌单',
  'kugouPlaylist': '酷狗歌单',
};

final class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.url,
    this.duration = Duration.zero,
    this.query = '',
    this.page = 1,
    required this.fetchedAt,
    this.provider = 'myfreemp3',
    this.downloadable = true,
    this.explicit = false,
    this.cover = '',
    this.lookupOnPlay = false,
  });

  final String id;
  final String title;
  final String artist;
  final Uri url;
  final Duration duration;
  final String query;
  final int page;
  final DateTime fetchedAt;
  final String provider;
  final bool downloadable;
  final bool explicit;
  final String cover;
  final bool lookupOnPlay;
  String get key => '$provider:$id';
  bool get searchOnly =>
      lookupOnPlay || musicPlaylistProviders.containsKey(provider);
  bool get canDownload =>
      downloadable &&
      !searchOnly &&
      !provider.startsWith('lx') &&
      !{'qqmp3', 'kugou'}.contains(provider);
  MusicTrack forPlaylistSearch() =>
      searchOnly ? this : _copy(url, fetchedAt, lookup: true);

  MusicTrack withUrl(Uri value) =>
      _copy(value, DateTime.now(), lookup: lookupOnPlay);

  MusicTrack _copy(Uri value, DateTime timestamp, {required bool lookup}) =>
      MusicTrack(
        id: id,
        title: title,
        artist: artist,
        url: value,
        duration: duration,
        query: query,
        page: page,
        fetchedAt: timestamp,
        provider: provider,
        downloadable: downloadable,
        explicit: explicit,
        cover: cover,
        lookupOnPlay: lookup,
      );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'url': url.toString(),
    'duration': duration.inMilliseconds,
    'query': query,
    'page': page,
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    'provider': provider,
    'downloadable': downloadable,
    'explicit': explicit,
    'cover': cover,
    if (lookupOnPlay) 'lookupOnPlay': true,
  };
  factory MusicTrack.fromJson(Map value) {
    for (final field in ['id', 'title', 'artist', 'url', 'query', 'provider']) {
      if (value[field] is! String) throw const FormatException('歌曲字段无效');
    }
    if ((value['id'] as String).isEmpty ||
        (value['title'] as String).trim().isEmpty ||
        (value['artist'] as String).length > 1000 ||
        (value['query'] as String).length > 100 ||
        !{
          'myfreemp3',
          'netease',
          'audius',
          'flacHi',
          'kugou',
          'archive',
          'lxHuibq',
          'qqmp3',
          'musicBox',
          'lxHuanyin',
          'lxQdy',
          'lxXinghai',
          'lxIkun',
          'lxExclusive',
          'lxHelloWorld',
          'lxHyw',
          'lxFlower',
          'lxGrass',
          'lxJuhe',
          ...musicPlaylistProviders.keys,
        }.contains(value['provider']) ||
        value['duration'] is! int ||
        (value['duration'] as int) < 0 ||
        (value['duration'] as int) > 86400000 ||
        value['page'] is! int ||
        (value['page'] as int) < 1 ||
        (value['page'] as int) > 1000 ||
        value['fetchedAt'] is! int ||
        (value['fetchedAt'] as int) < 0 ||
        (value['fetchedAt'] as int) > 8640000000000000) {
      throw const FormatException('歌曲记录无效');
    }
    final url = Uri.parse(value['url'] as String);
    if (!{'http', 'https'}.contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        (value['title'] as String).length > 1000 ||
        (value['id'] as String).length > 512) {
      throw const FormatException('歌曲记录无效');
    }
    return MusicTrack(
      id: value['id'] as String,
      title: value['title'] as String,
      artist: value['artist'] as String,
      url: url,
      duration: Duration(milliseconds: value['duration'] as int),
      query: value['query'] as String,
      page: value['page'] as int,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(value['fetchedAt'] as int),
      provider: value['provider'] as String,
      downloadable: value['downloadable'] == true,
      explicit: value['explicit'] == true,
      cover: value['cover'] as String? ?? '',
      lookupOnPlay: value['lookupOnPlay'] == true,
    );
  }
}

final class MusicSearchResult {
  const MusicSearchResult(this.tracks, {this.hasNext = false});
  final List<MusicTrack> tracks;
  final bool hasNext;
}
