final class MusicRecommendation {
  const MusicRecommendation(
    this.title,
    this.artist,
    this.cover, {
    this.description = '',
    this.id = '',
    this.rank,
    this.duration,
    this.vip = false,
    this.mv = false,
    this.trendType,
    this.trendValue = '',
  });
  final String title, artist, cover, description;
  final String id;
  final int? rank;
  final Duration? duration;
  final bool vip, mv;

  /// Source trend codes: 1 up, 2 down, 3 flat, 4 new, 5 re-entry, 6 up percent.
  final int? trendType;
  final String trendValue;
  String get query => '$title $artist'.trim();
  Map<String, String> toJson() => {
    'title': title,
    'artist': artist,
    'cover': cover,
    'description': description,
    if (id.isNotEmpty) 'id': id,
    if (rank != null) 'rank': '$rank',
    if (duration != null) 'seconds': '${duration!.inSeconds}',
    if (vip) 'vip': '1',
    if (mv) 'mv': '1',
    if (trendType != null) 'trendType': '$trendType',
    if (trendValue.isNotEmpty) 'trendValue': trendValue,
  };
  factory MusicRecommendation.fromJson(Map row) => MusicRecommendation(
    row['title'] as String,
    row['artist'] as String,
    row['cover'] as String,
    description: row['description'] as String? ?? '',
    id: row['id'] as String? ?? '',
    rank: int.tryParse('${row['rank'] ?? ''}'),
    duration: _seconds(row['seconds']),
    vip: row['vip'] == '1',
    mv: row['mv'] == '1',
    trendType: int.tryParse('${row['trendType'] ?? ''}'),
    trendValue: row['trendValue'] as String? ?? '',
  );

  static Duration? _seconds(Object? value) {
    final seconds = int.tryParse('$value');
    return seconds == null ? null : Duration(seconds: seconds.clamp(0, 86400));
  }
}