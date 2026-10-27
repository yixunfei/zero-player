import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../data/catalog_parser.dart';
import '../data/source_repository.dart';
import '../domain/source_catalog.dart';
import '../../live/data/live_repository.dart';

final class CatalogPreview {
  const CatalogPreview(this.url, this.text, this.catalog);
  final Uri url;
  final String text;
  final SourceCatalog catalog;
}

final class SubscriptionService {
  const SubscriptionService(this.network, this.repository);
  final DocumentClient network;
  final SourceRepository repository;
  static const parser = JsonSourceCatalogParser();

  Future<CatalogPreview> preview(
    Uri url, {
    CancellationToken? cancellation,
  }) async {
    final document = await network.get(url, cancellation: cancellation);
    return CatalogPreview(
      url,
      document.text,
      parser.parse(document.text, document.uri),
    );
  }

  Future<void> import(
    CatalogPreview preview,
    String name, {
    bool enableNew = false,
  }) async {
    await repository.applySubscription(
      preview.url,
      name,
      preview.text,
      preview.catalog.sources,
      enableNew: enableNew,
    );
    final live = LiveRepository(repository.db, network);
    final failures = <String>[];
    for (final entry in preview.catalog.lives) {
      try {
        await live.import(
          entry.name,
          entry.url,
          epg: entry.epg,
          headers: entry.headers,
        );
      } catch (_) {
        failures.add(entry.name);
      }
    }
    if (failures.isNotEmpty) {
      throw FormatException('点播配置及成功的直播列表已保存；直播导入失败：${failures.join('、')}');
    }
  }

  Future<List<CatalogPreview>> selectedChildren(
    List<CatalogReference> selected, {
    CancellationToken? cancellation,
    void Function(Uri, Object)? onFailure,
  }) async {
    final result = <CatalogPreview>[];
    final visited = <Uri>{};
    var totalBytes = 0;
    Future<void> walk(Uri uri, int depth) async {
      cancellation?.check();
      if (visited.contains(uri)) return;
      if (depth > 3 || visited.length >= 50) {
        throw const FormatException('多仓展开超过深度或数量限制');
      }
      visited.add(uri);
      final item = await preview(uri, cancellation: cancellation);
      totalBytes += item.text.length * 3;
      if (totalBytes > 20 * 1024 * 1024) {
        throw const FormatException('多仓累计体积超过限制');
      }
      if (result.fold<int>(0, (n, e) => n + e.catalog.sources.length) +
              item.catalog.sources.length >
          500) {
        throw const FormatException('源数量超过 500');
      }
      result.add(item);
      for (final child in item.catalog.references) {
        try {
          await walk(child.uri, depth + 1);
        } catch (error) {
          cancellation?.check();
          if (onFailure == null) rethrow;
          onFailure(child.uri, error);
        }
      }
    }

    for (final reference in selected) {
      try {
        await walk(reference.uri, 1);
      } catch (error) {
        cancellation?.check();
        if (onFailure == null) rethrow;
        onFailure(reference.uri, error);
      }
    }
    return result;
  }

  Future<void> refresh(Map<String, Object?> subscription) async {
    try {
      final item = await preview(Uri.parse(subscription['url'] as String));
      if (item.catalog.references.isNotEmpty && item.catalog.sources.isEmpty) {
        throw const FormatException('此入口包含子仓，请重新预览并选择子仓');
      }
      await import(item, subscription['name'] as String);
    } catch (_) {
      await repository.subscriptionFailure(
        subscription['id'] as String,
        '刷新失败，已保留上次成功内容',
      );
      rethrow;
    }
  }

  Future<void> refreshDue() async {
    for (final row in await repository.subscriptions()) {
      if (row['paused'] == 1) continue;
      final last = row['last_success'] as int? ?? 0;
      final due =
          DateTime.now().millisecondsSinceEpoch - last >
          (row['refresh_hours'] as int) * 3600000;
      if (due) {
        try {
          await refresh(row);
        } catch (_) {
          /* Snapshot retained. */
        }
      }
    }
  }
}
