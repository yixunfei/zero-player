import '../../catalog/domain/catalog_item.dart';
import '../../catalog/domain/vod_provider.dart';
import '../../sources/domain/video_source.dart';
import '../application/content_policy.dart';
import '../domain/supervision_rules.dart';

/// All user-facing provider results cross the same policy boundary. A category
/// lookup is made only for CMS records which omit the category's display name.
final class FilteringVodProvider implements VodProvider {
  FilteringVodProvider(this.inner, this.source, this.policy);
  final VodProvider inner;
  final VideoSource source;
  final ContentPolicy policy;
  Future<Map<String, String>>? _categoryLoad;

  Future<Map<String, String>> _categories() async {
    final cached = policy.categories(source.id);
    if (cached != null) return cached;
    return _categoryLoad ??= () async {
      try {
        final result = await inner.browse();
        policy.rememberCategories(source.id, result.categories);
        return result.categories;
      } catch (_) {
        // An unverified category must not silently become unrestricted.
        return <String, String>{};
      }
    }();
  }

  Future<CatalogItem> _classify(CatalogItem item) async {
    if (!policy.active || item.category.isNotEmpty || item.categoryId.isEmpty) {
      return item;
    }
    final category = (await _categories())[item.categoryId];
    if (category == null || category.isEmpty) {
      throw const ContentBlocked('内容分类尚未确认，暂不展示或播放');
    }
    return item.withCategory(category);
  }

  Future<CatalogPage> _page(CatalogPage page) async {
    final items = <CatalogItem>[];
    for (final raw in page.items) {
      try {
        final item = await _classify(raw);
        if (policy.itemAllowed(item)) items.add(item);
      } on ContentBlocked {
        /* Exclude unverified/blocked records. */
      }
    }
    policy.requireSource(source);
    return CatalogPage(items, page.pageCount);
  }

  @override
  Future<CatalogBrowse> browse({String category = '', int page = 1}) async {
    policy.requireSource(source);
    final result = await inner.browse(category: category, page: page);
    if (result.categories.isNotEmpty) {
      policy.rememberCategories(source.id, result.categories);
    }
    return CatalogBrowse(
      await _page(result.page),
      categories: {
        for (final entry in result.categories.entries)
          if (policy.textAllowed('', category: entry.value))
            entry.key: entry.value,
      },
      metadata: result.metadata,
    );
  }

  @override
  Future<CatalogPage> search(String query, {int page = 1}) async {
    policy.requireSource(source);
    if (!policy.textAllowed(query)) return const CatalogPage([], 1);
    return _page(await inner.search(query, page: page));
  }

  @override
  Future<CatalogItem> detail(String remoteId) async {
    policy.requireSource(source);
    final item = await _classify(await inner.detail(remoteId));
    policy.requireSource(source);
    policy.requireItem(item);
    return item;
  }

  @override
  Future<ResolvedMedia> resolve(Episode episode) async {
    policy.requireSource(source);
    if (!policy.textAllowed(episode.label)) throw const ContentBlocked();
    final media = await inner.resolve(episode);
    policy.requireSource(source);
    return media;
  }
}
