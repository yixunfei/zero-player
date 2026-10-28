import 'video_source.dart';

int compareRecommendedSources(VideoSource a, VideoSource b) {
  if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
  final name = a.displayName.compareTo(b.displayName);
  return name != 0 ? name : a.id.compareTo(b.id);
}
