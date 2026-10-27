import '../../catalog/data/provider_factory.dart';
import '../../sources/domain/video_source.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/cancellation_token.dart';
import 'recommendation_repository.dart';

Future<Recommendations> discoverCatalog(
  VideoSource source,
  DocumentClient network,
  String category, {
  bool filterAdult = true,
  int page = 1,
  CancellationToken? cancellation,
}) async {
  final provider = createVodProvider(
    source,
    network,
    cancellation: cancellation,
  );
  final data = await provider.browse(category: category, page: page);
  cancellation?.check();
  final categories = <String, String>{'': '全部'};
  for (final entry in data.categories.entries) {
    if (entry.value.isNotEmpty &&
        (!filterAdult || !adultContent(entry.value))) {
      categories[entry.key] = entry.value;
    }
  }
  final items = data.page.items.where(
    (i) => !filterAdult || !adultContent('${i.title} ${i.category}'),
  );
  return Recommendations(
    [
      for (final item in items)
        Recommendation(
          item.title,
          item.poster,
          '${item.year} ${item.category} ${item.remarks}'.trim(),
          id: item.id,
          description: item.description,
        ),
    ],
    categories: categories,
    hasMore: page < data.page.pageCount,
  );
}

bool adultContent(String text) => RegExp(
  r'成人|伦理片|情色|色情|里番|无码|有码|\bxxx\b',
  caseSensitive: false,
).hasMatch(text);
