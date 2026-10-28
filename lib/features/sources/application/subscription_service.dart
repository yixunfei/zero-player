import 'dart:async';
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

final class PartialCatalogImportException extends FormatException {
  const PartialCatalogImportException(super.message);
}

final class SubscriptionService {
  SubscriptionService(this.network, this.repository);
  final DocumentClient network;
  final SourceRepository repository;
  static const parser = JsonSourceCatalogParser();
  final _cancellation = CancellationToken();
  final _pending = <Future<void>>{};

  Future<CatalogPreview> preview(Uri url, {CancellationToken? cancellation}) =>
      _track(() async {
        final token = CancellationToken();
        final stopLifetime = _cancellation.listen(token.cancel);
        final stopCaller = cancellation?.listen(token.cancel);
        try {
          final document = await network.get(url, cancellation: token);
          token.check();
          return CatalogPreview(
            url,
            document.text,
            parser.parse(document.text, document.uri),
          );
        } finally {
          stopLifetime();
          stopCaller?.call();
        }
      });

  Future<void> import(
    CatalogPreview preview,
    String name, {
    bool enableNew = false,
  }) => _track(() async {
    if (preview.catalog.sources.isEmpty && preview.catalog.lives.isEmpty) {
      throw const FormatException('目录没有可导入内容，已保留上次成功内容');
    }
    await repository.applySubscription(
      preview.url,
      name,
      preview.text,
      preview.catalog.sources,
      enableNew: enableNew,
      replaceSources: preview.catalog.sources.isNotEmpty,
    );
    await _importLives(preview.catalog.lives);
  });

  Future<void> importLocal(CatalogPreview preview, {bool enableNew = false}) =>
      _track(() async {
        final urls = [
          ...preview.catalog.sources.map((entry) => entry.endpoint),
          ...preview.catalog.lives.map((entry) => entry.url),
          ...preview.catalog.lives.map((entry) => entry.epg).whereType<Uri>(),
        ];
        if (urls.any((uri) => uri.host == 'local-import.invalid')) {
          throw const FormatException('文件导入需要完整的 HTTP(S) 接口和直播地址');
        }
        await repository.db.atomic(() async {
          for (final source in preview.catalog.sources) {
            _cancellation.check();
            await repository.saveManual(
              source.name,
              source.endpoint,
              enabled: enableNew,
              kind: source.kind.name,
              classification: source.classification,
            );
          }
        }, tables: SourceRepository.tables);
        await _importLives(preview.catalog.lives);
      });

  Future<void> _importLives(List<LiveCatalogEntry> entries) async {
    final live = LiveRepository(repository.db, network);
    final failures = <String>[];
    for (final entry in entries) {
      _cancellation.check();
      try {
        await live.import(
          entry.name,
          entry.url,
          epg: entry.epg,
          headers: entry.headers,
          cancellation: _cancellation,
        );
      } catch (_) {
        _cancellation.check();
        failures.add(entry.name);
      }
    }
    if (failures.isNotEmpty) {
      throw PartialCatalogImportException(
        '已保存点播配置和成功的直播列表，失败的直播列表保留旧内容：${failures.join('、')}',
      );
    }
  }

  Future<List<CatalogPreview>> selectedChildren(
    List<CatalogReference> selected, {
    CancellationToken? cancellation,
    void Function(Uri, Object)? onFailure,
  }) => _track(() async {
    final result = <CatalogPreview>[];
    final visited = <Uri>{};
    var totalBytes = 0;
    Future<void> walk(Uri uri, int depth) async {
      _cancellation.check();
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
  });

  Future<void> refresh(Map<String, Object?> subscription) => _track(() async {
    try {
      final item = await preview(Uri.parse(subscription['url'] as String));
      if (item.catalog.references.isNotEmpty &&
          item.catalog.sources.isEmpty &&
          item.catalog.lives.isEmpty) {
        throw const FormatException('此入口包含子仓，请重新预览并选择子仓');
      }
      await import(item, subscription['name'] as String);
    } on PartialCatalogImportException catch (error) {
      _cancellation.check();
      await repository.subscriptionFailure(
        subscription['id'] as String,
        error.message,
      );
      rethrow;
    } catch (_) {
      _cancellation.check();
      await repository.subscriptionFailure(
        subscription['id'] as String,
        '刷新失败，已保留上次成功内容',
      );
      rethrow;
    }
  });

  Future<void> refreshDue() => _track(() async {
    for (final row in await repository.subscriptions()) {
      if (_cancellation.isCancelled) return;
      if (row['paused'] == 1) continue;
      final last = row['last_success'] as int? ?? 0;
      final due =
          DateTime.now().millisecondsSinceEpoch - last >
          (row['refresh_hours'] as int) * 3600000;
      if (due) {
        try {
          await refresh(row);
        } catch (_) {
          // The stored message distinguishes partial updates from full failure.
        }
      }
    }
  });

  Future<T> _track<T>(Future<T> Function() operation) async {
    _cancellation.check();
    final done = Completer<void>();
    _pending.add(done.future);
    try {
      return await operation();
    } finally {
      done.complete();
      _pending.remove(done.future);
    }
  }

  Future<void> close() async {
    _cancellation.cancel();
    await Future.wait(_pending.toList());
  }
}
