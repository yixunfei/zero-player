import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/application/live_probe.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/domain/channel_order.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/live/domain/live_health.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import '../../test_support/http_test_server.dart';

void main() {
  _orderingTests();
  _persistenceTests();
  _subscriptionStateTest();
  _missingFavoriteTest();
  group('probe', _probeTests);
}

void _missingFavoriteTest() {
  test(
    'missing favorites retain disable choice and cannot displace CCTV default',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      addTearDown(() async {
        http.close();
        await db.close();
      });
      final live = LiveRepository(db, DocumentClient(http));
      await live.importText(
        'old',
        Uri.parse('https://list.test/old'),
        'CCTV1,https://media.test/live.ts',
      );
      final old = (await live.channels()).single;
      await live.favorite(old, true);
      await live.removeList(old.listId);
      final missing = (await live.channels()).single;
      expect(channelGroup(missing), '暂不可用');
      expect(matchesChannel(missing, '央视', ''), isFalse);
      expect(matchesChannel(missing, '收藏', ''), isTrue);
      await LiveHealthRepository(db).setEnabled([old.id], false);
      final disabled = (await live.channels()).single;
      expect(disabled.health.enabled, isFalse);
      expect(matchesChannel(disabled, '已停用', ''), isTrue);
      expect(disabled.favorite, isTrue);
    },
  );
}

void _subscriptionStateTest() {
  test(
    'disabled subscriptions retain data and stay disabled after refresh and backup',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      addTearDown(() async {
        http.close();
        await db.close();
      });
      final live = LiveRepository(db, DocumentClient(http));
      final origin = Uri.parse('https://list.test/list');
      const text = 'CCTV1,https://media.test/live.ts';
      await live.importText('TV', origin, text);
      final channel = (await live.channels()).single;
      await live.favorite(channel, true);
      await live.setListEnabled(channel.listId, false);
      expect(await live.channels(), isEmpty);
      await live.importText('TV', origin, text);
      expect(await live.channels(), isEmpty);
      final backup = BackupService(db);
      final snapshot = await backup.preview(await backup.export());
      await live.setListEnabled(channel.listId, true);
      expect((await live.channels()).single.favorite, isTrue);
      await backup.restore(snapshot);
      expect((await live.lists()).single['enabled'], 0);
      expect(await live.channels(), isEmpty);
    },
  );
}

LiveChannel _channel(String name, {List<Uri>? urls, LiveHealth? health}) =>
    LiveChannel(
      id: name,
      listId: 'test',
      name: name,
      urls: urls ?? [Uri.parse('https://media.test/live.ts')],
      health: health ?? const LiveHealth(),
    );

void _orderingTests() {
  test(
    'CCTV natural order, group filtering and chosen fallback are stable',
    () {
      final channels = [
        'CCTV-10',
        '浙江卫视',
        'CGTN',
        'CCTV-5+',
        'CCTV-2',
        'CCTV-5',
        'CCTV-1',
      ].map(_channel).toList()..sort(compareChannels);
      expect(channels.map((c) => c.name), [
        'CCTV-1',
        'CCTV-2',
        'CCTV-5',
        'CCTV-5+',
        'CCTV-10',
        'CGTN',
        '浙江卫视',
      ]);
      final disabled = _channel(
        'CCTV1',
        health: const LiveHealth(enabled: false),
      );
      expect(matchesChannel(disabled, '央视', ''), isFalse);
      expect(matchesChannel(disabled, '已停用', 'cctv'), isTrue);
      final first = Uri.parse('https://media.test/first.ts');
      final second = Uri.parse('https://media.test/second.ts');
      final chosen = _channel(
        'CCTV1',
        urls: [first, second],
        health: LiveHealth(preferredUrl: second.toString()),
      );
      expect(chosen.playbackUrls, [second, first]);
      expect(chosen.urls, [first, second]);
    },
  );
}

void _persistenceTests() {
  test(
    'disable, probe, refresh, changed URLs and backup preserve personal choices',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      addTearDown(() async {
        http.close();
        await db.close();
      });
      final live = LiveRepository(db, DocumentClient(http));
      final health = LiveHealthRepository(db);
      final origin = Uri.parse('https://list.test/list.m3u');
      const playlist = 'CCTV1,https://media.test/live.ts';
      await live.importText('TV', origin, playlist);
      final channel = (await live.channels()).single;
      await live.favorite(channel, true);
      await live.watched(channel);
      await health.setEnabled([channel.id], false);
      await health.record(
        channel,
        const LiveHealth(
          availability: LiveAvailability.responding,
          latencyMs: 12,
          preferredUrl: 'https://media.test/live.ts',
          message: 'received',
        ),
      );
      await live.importText('TV', origin, playlist);
      var saved = (await live.channels()).single;
      expect(saved.health.enabled, isFalse);
      expect(saved.health.availability, LiveAvailability.responding);
      expect(saved.watchedAt, isNotNull);
      expect(saved.favorite, isTrue);
      final backup = BackupService(db);
      final snapshot = await backup.preview(await backup.export());
      await health.setEnabled([channel.id], true);
      await backup.restore(snapshot);
      expect((await live.channels()).single.health.enabled, isFalse);
      await live.importText('TV', origin, 'CCTV1,https://media.test/new.ts');
      saved = (await live.channels()).single;
      expect(saved.id, channel.id);
      expect(saved.health.enabled, isFalse);
      expect(saved.health.availability, LiveAvailability.unknown);
      expect(saved.health.preferredUrl, isNull);
      final invalid = jsonDecode(await backup.export()) as Map;
      invalid['tables']['app_meta'] = [
        {'key': 'live_state:x', 'value': '{"enabled":"false"}'},
      ];
      await expectLater(
        backup.preview(jsonEncode(invalid)),
        throwsFormatException,
      );
    },
  );
}

void _probeTests() {
  late AppDatabase db;
  late MediaHttpClient http;
  late LiveProbe probe;
  late HttpTestServer server;
  late Completer<void> stalled, release;
  setUp(() async {
    db = AppDatabase.memory();
    http = MediaHttpClient();
    stalled = Completer<void>();
    release = Completer<void>();
    server = await HttpTestServer.start((request) async {
      switch (request.uri.path) {
        case '/ok.ts':
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.add(List.filled(188, 0x47));
        case '/busy':
          request.response.statusCode = 503;
        case '/rate':
          request.response.statusCode = 429;
        case '/slow':
          if (!stalled.isCompleted) stalled.complete();
          await release.future;
        default:
          request.response.statusCode = 404;
      }
    });
    probe = LiveProbe(
      http,
      LiveHealthRepository(db),
      networkTimeout: const Duration(milliseconds: 200),
    );
  });
  tearDown(() async {
    if (!release.isCompleted) release.complete();
    await probe.close();
    http.close();
    await server.close();
    await db.close();
  });
  test('failed primary with responsive alternative stays enabled', () async {
    final channel = _channel(
      'one',
      urls: [server.baseUri.resolve('gone'), server.baseUri.resolve('ok.ts')],
    );
    final result = await probe.check(channel, CancellationToken());
    expect(result.availability, LiveAvailability.responding);
    expect(result.preferredUrl, server.baseUri.resolve('ok.ts').toString());
    expect(result.latencyMs, isNonNegative);
  });
  test(
    'all explicit failures unavailable; untested alternatives inconclusive',
    () async {
      final token = CancellationToken();
      final result = await probe.check(
        _channel('gone', urls: [server.baseUri.resolve('404')]),
        token,
      );
      expect(result.availability, LiveAvailability.unavailable);
      final partial = await probe.check(
        _channel(
          'partial',
          urls: List.generate(4, (i) => server.baseUri.resolve('gone$i')),
        ),
        token,
      );
      expect(partial.availability, LiveAvailability.inconclusive);
      expect(server.calls['/gone3'], isNull);
    },
  );
  test('transient failures remain uncertain', () async {
    for (final path in ['slow', 'busy', 'rate']) {
      final result = await probe.check(
        _channel(path, urls: [server.baseUri.resolve(path)]),
        CancellationToken(),
      );
      expect(result.availability, LiveAvailability.inconclusive, reason: path);
    }
  });
  test('shutdown cancels outstanding probe without writing failure', () async {
    final work = probe.check(
      _channel('closing', urls: [server.baseUri.resolve('slow')]),
      CancellationToken(),
    );
    final cancelled = expectLater(work, throwsA(isA<RequestCancelled>()));
    await stalled.future;
    await probe.close();
    await cancelled;
    expect(
      await db.rows("SELECT * FROM app_meta WHERE key='live_state:closing'"),
      isEmpty,
    );
  });
}
