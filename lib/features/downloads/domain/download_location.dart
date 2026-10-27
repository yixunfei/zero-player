import '../../catalog/domain/catalog_item.dart';

final class DownloadLocation {
  const DownloadLocation(this.item, this.line, this.episode, this.headers);
  final CatalogItem item;
  final PlayLine line;
  final Episode episode;
  final Map<String, String> headers;
}
