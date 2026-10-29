import 'video_source.dart';

/// One priority policy for scheduling and displaying channel results.
int searchSourceTier(VideoSource source, {String? entryId}) {
  if (source.id == entryId) return 0;
  if (source.favorite) return 1;
  if (source.apiOk && !source.possiblyInvalid) return 2;
  return 3;
}

int compareSearchSources(VideoSource a, VideoSource b, {String? entryId}) {
  final tier = searchSourceTier(
    a,
    entryId: entryId,
  ).compareTo(searchSourceTier(b, entryId: entryId));
  if (tier != 0) return tier;
  final failures = a.failures.compareTo(b.failures);
  if (failures != 0) return failures;
  final latency = (a.latencyMs ?? 999999).compareTo(b.latencyMs ?? 999999);
  return latency != 0 ? latency : compareRecommendedSources(a, b);
}

String searchSourceLabel(VideoSource source, {String? entryId}) =>
    switch (searchSourceTier(source, entryId: entryId)) {
      0 => '入口渠道',
      1 => '收藏渠道',
      2 => '可用渠道',
      _ => '未知渠道',
    };

int compareRecommendedSources(VideoSource a, VideoSource b) {
  if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
  final name = a.displayName.compareTo(b.displayName);
  return name != 0 ? name : a.id.compareTo(b.id);
}
