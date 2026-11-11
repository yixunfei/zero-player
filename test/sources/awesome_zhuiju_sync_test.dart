import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/domain/live_health.dart';
import 'package:zero_player/features/sources/application/awesome_zhuiju_discovery.dart';
import 'package:zero_player/features/sources/application/awesome_zhuiju_sync.dart';
import 'package:zero_player/features/sources/application/awesome_zhuiju_verification.dart';
import 'package:zero_player/features/sources/application/subscription_service.dart';
import 'package:zero_player/features/sources/data/awesome_zhuiju_index.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';

import '../../test_support/http_test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('only same-URL reachable entries from supported categories qualify', () {
    final a = Uri.parse('https://example.test/config');
    final b = a.resolve('/b');
    final c = a.resolve('/c');
    final d = a.resolve('/d');
    final e = a.resolve('/e');
    final index = _index(
      [
        _resource('accepted', a),
        _resource('restricted', b),
        _resource('removed', c, removed: true),
        _resource('changed', d),
        _resource('unrelated', e, category: 'video_app'),
      ],
      [
        _status('accepted', a),
        _status('restricted', b, status: 'restricted'),
        _status('removed', c),
        _status('changed', d.resolve('/old')),
        _status('unrelated', e),
      ],
    );
    expect(index.candidates.map((r) => r.uri), [a]);
    expect(
      index.blocked,
      containsAll([
        AwesomeZhuijuIndex.identity(b),
        AwesomeZhuijuIndex.identity(c),
      ]),
    );
    expect(index.skipped, 3);
    expect(
      AwesomeZhuijuIndex.videoIdentity(
        'cms',
        Uri.parse(
          'https://www.huyaapi.com/api.php/provide/vod/from/hym3u8?ac=list',
        ),
      ),
      AwesomeZhuijuIndex.videoIdentity(
        'cms',
        Uri.parse('https://www.huyaapi.com/api.php/provide/vod/'),
      ),
    );
  });

  _manualSyncTest();
}

void _manualSyncTest() {
  test(
    'manual sync saves only new twice-decoded channels and skips background refresh',
    () async {
      final server = await _server();
      final origin = Uri.parse(
        server.baseUri.replace(host: 'localhost').origin,
      );
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final network = DocumentClient(http);
      final sources = SourceRepository(db);
      final live = LiveRepository(db, network);
      final subscriptions = SubscriptionService(network, sources, live: live);
      final catalog = origin.resolve('/config');
      final blocked = origin.resolve('/blocked');
      var loads = 0;
      final decodeCalls = <String, int>{};
      var cancelOnDecode = true;
      final sync = AwesomeZhuijuSync(
        sources,
        live,
        AwesomeZhuijuDiscovery(sources, live, subscriptions),
        AwesomeZhuijuVerification(network, (uri, _, token) async {
          if (cancelOnDecode) {
            token.cancel();
            token.check();
          }
          decodeCalls.update(uri.path, (n) => n + 1, ifAbsent: () => 1);
          return uri.path == '/good.ts';
        }),
        load: (_) async {
          loads++;
          return _index(
            [_resource('root', catalog)],
            [
              _status('root', catalog),
              _status('old', blocked, status: 'unreachable'),
            ],
          );
        },
      );
      addTearDown(() async {
        await sync.close();
        await subscriptions.close();
        http.close();
        await server.close();
        await db.close();
      });
      await live.importText(
        'existing',
        origin.resolve('/existing'),
        'Duplicate,$origin/dup.ts',
      );
      expect(await sync.lastResult(), isNull);
      await subscriptions.refreshDue();
      expect(loads, 0);
      await expectLater(
        sync.sync(CancellationToken()),
        throwsA(isA<RequestCancelled>()),
      );
      expect(await sync.lastResult(), isNull);
      expect((await live.lists()).length, 1);

      cancelOnDecode = false;
      final report = await sync.sync(CancellationToken());
      expect(report['channelsAdded'], 1);
      final channel = (await live.channels()).singleWhere(
        (e) => e.name == 'Fresh',
      );
      expect(channel.health.availability, LiveAvailability.responding);
      expect(decodeCalls, {'/good.ts': 2, '/bad.ts': 1});
      expect(server.calls['/dup.ts'], isNull);
      expect(server.calls['/blocked'], isNull);

      final row = (await sources.subscriptions()).single;
      await sources.pauseSubscription(row['id'] as String, false);
      await db.write('UPDATE subscriptions SET last_success=0');
      await subscriptions.refreshDue();
      expect(loads, 2);
      final repeat = await sync.sync(CancellationToken());
      expect(repeat['channelsAdded'], 0);
      expect(decodeCalls, {'/good.ts': 2, '/bad.ts': 1});
    },
  );
}

Future<HttpTestServer> _server() => HttpTestServer.start((request) async {
  final origin = request.requestedUri.origin;
  switch (request.uri.path) {
    case '/config':
      request.response.write(
        jsonEncode({
          'urls': [
            {'name': 'blocked', 'url': '$origin/blocked'},
          ],
          'lives': [
            {'name': 'Fixture', 'url': '$origin/playlist'},
          ],
        }),
      );
    case '/playlist':
      request.response.write(
        'Duplicate,$origin/dup.ts\nFresh,$origin/good.ts\nBroken,$origin/bad.ts',
      );
    case '/good.ts':
    case '/bad.ts':
      request.response.headers.contentType = ContentType('video', 'mp2t');
      request.response.add([0x47, ...List.filled(187, 0)]);
    default:
      request.response.statusCode = 404;
  }
});

Map<String, Object?> _resource(
  String id,
  Uri url, {
  bool removed = false,
  String category = 'tvbox_config',
}) => {
  'id': id,
  'name': id,
  'url': '$url',
  'category': category,
  'verification': {'status': removed ? 'removed' : 'caution'},
};
Map<String, Object?> _status(
  String id,
  Uri url, {
  String status = 'reachable',
}) => {'resource_id': id, 'url': '$url', 'status': status};
AwesomeZhuijuIndex _index(List<Map> resources, List<Map> results) =>
    AwesomeZhuijuIndex.parse(
      {'version': 1, 'resources': resources},
      {
        'version': 1,
        'generated_at': '2026-11-11T00:00:00Z',
        'results': results,
      },
    );
