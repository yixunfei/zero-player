import 'catalog_item.dart';

final class CatalogBrowse {
  const CatalogBrowse(
    this.page, {
    this.categories = const {},
    this.metadata = const {},
  });
  final CatalogPage page;
  final Map<String, String> categories;
  final Map metadata;
}

final class ResolvedMedia {
  const ResolvedMedia(this.uri, {this.headers = const {}});
  final Uri uri;
  final Map<String, String> headers;
}

abstract interface class VodProvider
    implements VodSearchProvider, VodDetailProvider {
  Future<CatalogBrowse> browse({String category = '', int page = 1});
  Future<ResolvedMedia> resolve(Episode episode);
}
