final class MusicRecommendation {
  const MusicRecommendation(
    this.title,
    this.artist,
    this.cover, {
    this.description = '',
  });
  final String title, artist, cover, description;
  String get query => '$title $artist'.trim();
  Map<String, String> toJson() => {
    'title': title,
    'artist': artist,
    'cover': cover,
    'description': description,
  };
  factory MusicRecommendation.fromJson(Map row) => MusicRecommendation(
    row['title'] as String,
    row['artist'] as String,
    row['cover'] as String,
    description: row['description'] as String? ?? '',
  );
}
