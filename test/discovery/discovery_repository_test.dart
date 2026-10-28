import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/discovery/data/catalog_discovery.dart';
import 'package:zero_player/features/discovery/data/recommendation_repository.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import '../../test_support/http_test_server.dart';

void main() {
  _requestTests();
  _cacheTests();
  _settingsTests();
}

void _requestTests() {
  test(
    'Douban offsets advance and known payload preserves subject identity',
    () {
      expect(
        recommendationUri('douban', 'us', 3).queryParameters,
        containsPair('page_start', '${2 * recommendationPageSize}'),
      );
      expect(recommendationUri('douban', 'us', 3).queryParameters['tag'], '美剧');
      final items = parseRecommendations('douban', {
        'subjects': [
          {
            'title': '电影',
            'id': '42',
            'cover': 'https://img3.doubanio.com/poster.jpg',
            'rate': '8.1',
          },
        ],
      });
      expect(items.single.id, '42');
      expect(items.single.poster, contains('poster.jpg'));
    },
  );
  test(
    'CMS passes requested page/category and resolves relative covers',
    () async {
      String? page;
      String? category;
      final server = await HttpTestServer.start((r) {
        page = r.uri.queryParameters['pg'];
        category = r.uri.queryParameters['t'];
        r.response.write(
          jsonEncode({
            'pagecount': 3,
            'class': [
              {'type_id': 1, 'type_name': '电影'},
              {'type_id': 2, 'type_name': '成人'},
            ],
            'list': [
              {
                'vod_id': 7,
                'vod_name': 'A',
                'vod_pic': '/poster.jpg',
                'type_name': '电影',
              },
            ],
          }),
        );
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final source = VideoSource(
        id: 'a',
        name: 'A',
        endpoint: server.baseUri.resolve('api'),
      );
      final result = await discoverCatalog(
        source,
        DocumentClient(http),
        '1',
        page: 2,
      );
      expect(page, '2');
      expect(category, '1');
      expect(result.hasMore, isTrue);
      expect(result.items.single.poster, '${server.baseUri}poster.jpg');
      expect(result.categories.containsKey('2'), isFalse);
      expect(
        (await discoverCatalog(
          source,
          DocumentClient(http),
          '1',
          page: 3,
        )).hasMore,
        isFalse,
      );
      http.close();
      await server.close();
    },
  );
}

void _cacheTests() {
  test(
    'first-page cache stays bounded; page two failures never replay page one',
    () async {
      var failing = false;
      final server = await HttpTestServer.start((r) {
        if (failing) {
          r.response.statusCode = 403;
          return;
        }
        r.response.write(
          jsonEncode({
            'subjects': List.generate(
              24,
              (i) => {'id': '$i', 'title': 'A$i', 'cover': ''},
            ),
          }),
        );
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final db = AppDatabase.memory();
      final repo = RecommendationRepository(
        DocumentClient(http),
        db,
        endpoint: (_, _, _) => server.baseUri,
      );
      final result = await repo.load('douban');
      expect(result.hasMore, isTrue);
      for (var i = 0; i < 34; i++) {
        await repo.load('douban', type: 'test$i');
      }
      expect(
        (await db.rows(
          'SELECT COUNT(*) AS n FROM recommendation_cache',
        )).single['n'],
        32,
      );
      failing = true;
      final cached = await repo.load('douban', type: 'test33');
      expect(cached.cached, isTrue);
      expect(cached.hasMore, isFalse);
      await expectLater(
        repo.load('douban', type: 'test33', page: 2),
        throwsA(isA<RemoteFailure>()),
      );
      http.close();
      await server.close();
      await db.close();
    },
  );
  test(
    'cancellation cannot recover from cache or write a late result',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      final server = await HttpTestServer.start((r) async {
        started.complete();
        await finish.future;
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final db = AppDatabase.memory();
      final repo = RecommendationRepository(
        DocumentClient(http),
        db,
        endpoint: (_, _, _) => server.baseUri,
      );
      final token = CancellationToken();
      final result = expectLater(
        repo.load('douban', cancellation: token),
        throwsA(isA<RequestCancelled>()),
      );
      await started.future;
      token.cancel();
      await result;
      finish.complete();
      expect(await db.rows('SELECT * FROM recommendation_cache'), isEmpty);
      http.close();
      await server.close();
      await db.close();
    },
  );
  test(
    'non-paginated providers return end without any page-two network call',
    () async {
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final db = AppDatabase.memory();
      final repo = RecommendationRepository(
        DocumentClient(http),
        db,
        endpoint: (_, _, _) => throw StateError('unexpected'),
      );
      for (final provider in ['bangumi', 'hot', 'off']) {
        expect((await repo.load(provider, page: 2)).hasMore, isFalse);
      }
      http.close();
      await db.close();
    },
  );
}

void _settingsTests() {
  test(
    'startup preferences survive reload and validated backup round trip',
    () async {
      final db = AppDatabase.memory();
      final settings = SettingsController(db);
      await settings.update({
        'homeChannel': 'local-source',
        'homeLayout': 'aggregate',
      });
      final restored = SettingsController(db);
      await restored.load();
      expect(restored.value.homeChannel, 'local-source');
      expect(restored.value.homeLayout, 'aggregate');
      final backup = BackupService(db);
      final snapshot = await backup.preview(await backup.export());
      await settings.update({'homeChannel': '', 'homeLayout': 'single'});
      await backup.restore(snapshot);
      await settings.load();
      expect(settings.value.homeChannel, 'local-source');
      expect(settings.value.homeLayout, 'aggregate');
      settings.dispose();
      restored.dispose();
      await db.close();
    },
  );
}
