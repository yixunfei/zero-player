/// Keep the most recently introduced alternatives without accumulating duplicates.
List<Uri> appendChannelUrls(Iterable<Uri> previous, Iterable<Uri> incoming) {
  final urls = previous.toSet();
  for (final uri in incoming) {
    if (!urls.add(uri)) continue;
    if (urls.length > 100) urls.remove(urls.first);
  }
  return urls.toList();
}
