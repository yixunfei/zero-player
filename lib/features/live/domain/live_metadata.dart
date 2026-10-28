import 'dart:convert';

/// Publisher declarations; stream observations live separately in LiveHealth.
final class LiveMetadata {
  const LiveMetadata({
    this.languages = const [],
    this.countries = const [],
    this.categories = const [],
    this.resolution = '',
  });
  final List<String> languages, countries, categories;
  final String resolution;

  factory LiveMetadata.fromAttributes(Map<String, String> attrs) {
    List<String> values(String key) => (attrs[key] ?? '')
        .split(RegExp(r'[,;]'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    final resolution = attrs['tvg-resolution'] ?? '';
    return LiveMetadata(
      languages: values('tvg-language'),
      countries: values('tvg-country'),
      categories: values('group-title'),
      resolution: RegExp(r'^\d+[xX]\d+$').hasMatch(resolution)
          ? resolution
          : '',
    );
  }

  Map<String, Object> toJson() => {
    'languages': languages,
    'countries': countries,
    'categories': categories,
    'resolution': resolution,
  };
  factory LiveMetadata.decode(Object? value, List<Uri> urls) {
    try {
      final data = jsonDecode(value as String) as Map;
      if (data['signature'] != urls.join('|')) return const LiveMetadata();
      return LiveMetadata(
        languages: List<String>.from(data['languages'] ?? []),
        countries: List<String>.from(data['countries'] ?? []),
        categories: List<String>.from(data['categories'] ?? []),
        resolution: data['resolution'] as String? ?? '',
      );
    } catch (_) {
      return const LiveMetadata();
    }
  }
}
