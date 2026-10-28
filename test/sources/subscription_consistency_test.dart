import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/sources/application/subscription_service.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/sources/domain/source_catalog.dart';

import '../../test_support/http_test_server.dart';

void main() {
  _refreshTests();
  _pauseTests();
  _localImportTests();
  _invalidLocalAddressTest();
  _changeTests();
  _closeTest();
}

void _refreshTests() {
  test(
    'empty refresh preserves subscription snapshot and source membership',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.seed();
      fixture.responses['/catalog'] = jsonEncode({'sources': []});
      await expectLater(
        fixture.service.refresh((await fixture.sources.subscriptions()).single),
        throwsFormatException,
      );
      expect((await fixture.sources.all()).single.name, 'old');
      expect(
        (await fixture.sources.subscriptions()).single['snapshot'],
        _catalog('old'),
      );
    },
  );

  test(
    'partial refresh reports saved sources while preserving failed live lists',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.seed();
      await fixture.live.importText(
        'bad',
        fixture.uri('/bad'),
        'OLD,https://media.test/old',
      );
      fixture.responses['/good'] = 'NEW,https://media.test/new';
      fixture.responses['/catalog'] = _catalog(
        'new',
        lives: [
          {'name': 'good', 'url': fixture.uri('/good').toString()},
          {'name': 'bad', 'url': fixture.uri('/bad').toString()},
        ],
      );
      await expectLater(
        fixture.service.refresh((await fixture.sources.subscriptions()).single),
        throwsA(isA<PartialCatalogImportException>()),
      );
      expect((await fixture.sources.all()).single.name, 'new');
      expect(
        (await fixture.live.channels()).map((channel) => channel.name),
        containsAll(['OLD', 'NEW']),
      );
      final row = (await fixture.sources.subscriptions()).single;
      expect(row['error'], contains('已保存点播配置'));
      expect(row['error'], contains('失败的直播列表保留旧内容'));
    },
  );

  test(
    'a live-only catalog refresh cannot erase existing VOD members',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.seed();
      fixture.responses['/good'] = 'TV,https://media.test/live';
      fixture.responses['/catalog'] = jsonEncode({
        'lives': [
          {'name': 'TV', 'url': fixture.uri('/good').toString()},
        ],
      });
      await fixture.service.refresh(
        (await fixture.sources.subscriptions()).single,
      );
      expect((await fixture.sources.all()).single.name, 'old');
      expect((await fixture.live.channels()).single.name, 'TV');
    },
  );
}

void _pauseTests() {
  test(
    'successful refresh resumes automatic pause but preserves manual pause',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.seed();
      final id = (await fixture.sources.subscriptions()).single['id'] as String;
      for (var i = 0; i < 3; i++) {
        await fixture.sources.subscriptionFailure(id, 'failed');
      }
      expect((await fixture.sources.subscriptions()).single['paused'], 1);
      fixture.responses['/catalog'] = _catalog('new');
      await fixture.service.refresh(
        (await fixture.sources.subscriptions()).single,
      );
      expect((await fixture.sources.subscriptions()).single['paused'], 0);
      await fixture.sources.pauseSubscription(id, true);
      for (var i = 0; i < 3; i++) {
        await fixture.sources.subscriptionFailure(id, 'manual retry failed');
      }
      await fixture.service.refresh(
        (await fixture.sources.subscriptions()).single,
      );
      expect((await fixture.sources.subscriptions()).single['paused'], 1);
    },
  );

  test('batch enable removes stale failure backoff', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.seed();
    final source = (await fixture.sources.all()).single;
    await fixture.db.write(
      'INSERT INTO source_health(source_id,failures,retry_after) VALUES(?,?,?)',
      [
        source.id,
        4,
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      ],
    );
    await fixture.sources.batch([source.id], enabled: true);
    final enabled = (await fixture.sources.find(source.id))!;
    expect(enabled.failures, 0);
    expect(enabled.retryAfter, isNull);
    expect(enabled.available, isTrue);
  });
}

void _localImportTests() {
  test(
    'local catalogs create manual sources and real live lists without a fake subscription',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      fixture.responses['/live'] = 'TV,https://media.test/live';
      final text = _catalog(
        'local',
        lives: [
          {'name': 'TV', 'url': fixture.uri('/live').toString()},
        ],
      );
      final origin = Uri.parse('https://local-import.invalid/');
      await fixture.service.importLocal(
        CatalogPreview(
          origin,
          text,
          SubscriptionService.parser.parse(text, origin),
        ),
        enableNew: true,
      );
      expect(await fixture.sources.subscriptions(), isEmpty);
      expect(
        (await fixture.db.rows('SELECT manual FROM sources')).single['manual'],
        1,
      );
      expect(
        (await fixture.live.lists()).single['url'],
        fixture.uri('/live').toString(),
      );
    },
  );

  test(
    'relative live URL is diagnosed while selected valid sources can be saved',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final origin = Uri.parse('https://local-import.invalid/');
      final text = _catalog(
        'local',
        lives: [
          {'name': 'TV', 'url': 'live.m3u'},
        ],
      );
      final catalog = SubscriptionService.parser.parse(text, origin);
      expect(catalog.lives, isEmpty);
      expect(catalog.diagnostics.single.reason, contains('HTTP(S)'));
      await fixture.service.importLocal(CatalogPreview(origin, text, catalog));
      expect((await fixture.sources.all()).single.name, 'local');
      expect(await fixture.sources.subscriptions(), isEmpty);
      expect(await fixture.live.lists(), isEmpty);
    },
  );
}

void _invalidLocalAddressTest() {
  test(
    'unresolved local import base is rejected before any source is saved',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final origin = Uri.parse('https://local-import.invalid/');
      final text = _catalog('local');
      final parsed = SubscriptionService.parser.parse(text, origin);
      final catalog = SourceCatalog(
        sources: parsed.sources,
        references: [],
        diagnostics: [],
        lives: [LiveCatalogEntry('TV', origin.resolve('live.m3u'))],
      );
      await expectLater(
        fixture.service.importLocal(CatalogPreview(origin, text, catalog)),
        throwsFormatException,
      );
      expect(await fixture.sources.all(), isEmpty);
      expect(await fixture.sources.subscriptions(), isEmpty);
      expect(await fixture.live.lists(), isEmpty);
    },
  );
}

void _changeTests() {
  test(
    'download and settings writes do not reload source subscribers',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      var notifications = 0;
      final subscription = fixture.sources.changes.listen(
        (_) => notifications++,
      );
      addTearDown(subscription.cancel);
      await fixture.db.write('UPDATE downloads SET bytes=bytes');
      await fixture.db.write('INSERT INTO settings VALUES(?,?)', [
        'theme',
        '"dark"',
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);
      await fixture.seed();
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      fixture.db.changed();
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 2);
    },
  );
}

void _closeTest() {
  test(
    'close cancels background refresh without writing a failure state',
    () async {
      final requested = Completer<void>();
      final release = Completer<void>();
      final server = await HttpTestServer.start((request) async {
        requested.complete();
        await release.future;
        request.response.write(_catalog('new'));
      });
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final sources = SourceRepository(db);
      final service = SubscriptionService(DocumentClient(http), sources);
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await service.close();
        http.close();
        await server.close();
        await db.close();
      });
      final text = _catalog('old');
      await service.import(
        CatalogPreview(
          server.baseUri,
          text,
          SubscriptionService.parser.parse(text, server.baseUri),
        ),
        'catalog',
      );
      await db.write('UPDATE subscriptions SET last_success=0');
      final refresh = service.refreshDue();
      await requested.future;
      await service.close().timeout(const Duration(seconds: 2));
      await refresh;
      expect((await sources.all()).single.name, 'old');
      expect((await sources.subscriptions()).single['failures'], 0);
    },
  );
}

String _catalog(String name, {List<Map<String, String>> lives = const []}) =>
    jsonEncode({
      'sources': [
        {'name': name, 'url': 'https://media.test/$name/api'},
      ],
      'lives': lives,
    });

final class _Fixture {
  _Fixture(this.server, this.responses);
  final HttpTestServer server;
  final Map<String, String> responses;
  final db = AppDatabase.memory();
  final http = MediaHttpClient(allowPrivateNetworks: true);
  late final sources = SourceRepository(db);
  late final live = LiveRepository(db, DocumentClient(http));
  late final service = SubscriptionService(DocumentClient(http), sources);
  Uri uri(String path) => server.baseUri.resolve(path);

  static Future<_Fixture> create() async {
    final responses = <String, String>{};
    final server = await HttpTestServer.start((request) {
      final text = responses[request.uri.path];
      if (text == null) {
        request.response.statusCode = 404;
      } else {
        request.response.write(text);
      }
    });
    return _Fixture(server, responses);
  }

  Future<void> seed() {
    final text = _catalog('old');
    final origin = uri('/catalog');
    return service.import(
      CatalogPreview(
        origin,
        text,
        SubscriptionService.parser.parse(text, origin),
      ),
      'catalog',
    );
  }

  Future<void> close() async {
    await service.close();
    http.close();
    await server.close();
    await db.close();
  }
}
