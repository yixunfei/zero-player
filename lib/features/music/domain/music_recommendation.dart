final class MusicRecommendation {
  const MusicRecommendation(
    this.title,
    this.artist,
    this.cover, {
    this.description = '',
    this.id = '',
    this.rank,
  });
  final String title, artist, cover, description;
  final String id;
  final int? rank;
  String get query => '$title $artist'.trim();
  Map<String, String> toJson() => {
    'title': title,
    'artist': artist,
    'cover': cover,
    'description': description,
    if (id.isNotEmpty) 'id': id,
    if (rank != null) 'rank': '$rank',
  };
  factory MusicRecommendation.fromJson(Map row) => MusicRecommendation(
    row['title'] as String,
    row['artist'] as String,
    row['cover'] as String,
    description: row['description'] as String? ?? '',
    id: row['id'] as String? ?? '',
    rank: int.tryParse('${row['rank'] ?? ''}'),
  );
}
