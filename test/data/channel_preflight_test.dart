import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/application/channel_preflight.dart';
import 'package:zero_player/features/live/application/live_probe.dart';
import 'package:zero_player/features/live/data/live_audit_defaults.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/domain/channel_probe_signature.dart';
import 'package:zero_player/features/live/domain/live_health.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import '../../test_support/http_test_server.dart';

void main() {
  _versionedProofTest();
  _cancelledUpdateTest();
  test(
    'bundled proof enables only passed channels and survives backups',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.close);
      final live = f.repository();
      await live.importText('TV', f.list, f.playlist('ok'), verify: false);
      var channel = (await live.channels()).single;
      expect(channel.health.enabled, isTrue);
      await live.importText('TV', f.list, f.playlist('new'), verify: false);
      channel = (await live.channels()).single;
      expect(channel.health.enabled, isFalse);
      expect(channel.health.availability, LiveAvailability.unknown);
      await expectLater(
        f.health.setEnabled([channel.id], true),
        throwsFormatException,
      );
      final backup = BackupService(f.db);
      await backup.preview(await backup.export());
    },
  );
  test(
    'updated failed channel stays disabled until actual media succeeds',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.close);
      final live = f.repository();
      await live.importText('TV', f.list, f.playlist('bad'));
      expect((await live.channels()).single.health.enabled, isFalse);
      f.block = Completer<void>();
      f.entered = Completer<void>();
      final update = live.importText('TV', f.list, f.playlist('new'));
      await f.entered!.future;
      expect((await live.channels()).single.health.enabled, isFalse);
      f.block!.complete();
      await update;
      var channel = (await live.channels()).single;
      expect(channel.health.enabled, isTrue);
      expect(channel.health.availability, LiveAvailability.responding);
      await f.health.setEnabled([channel.id], false);
      await live.importText('TV', f.list, f.playlist('newer'));
      channel = (await live.channels()).single;
      expect(
        channel.health.enabled,
        isFalse,
        reason: 'manual disable survives automatic recovery',
      );
      await f.probe.check(channel, CancellationToken(), enableResponding: true);
      expect((await live.channels()).single.health.enabled, isTrue);
    },
  );
  test(
    'header changes invalidate proof and current unavailable result closes older success',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.close);
      final live = f.repository();
      await live.importText('TV', f.list, f.playlist('ok'), verify: false);
      await live.importText(
        'TV',
        f.list,
        f.playlist('ok'),
        headers: {'User-Agent': 'changed'},
        verify: false,
      );
      var c = (await live.channels()).single;
      expect(c.health.enabled, isFalse);
      await f.probe.check(c, CancellationToken());
      c = (await live.channels()).single;
      expect(c.health.enabled, isTrue);
      f.fail = true;
      await f.probe.check(c, CancellationToken());
      expect((await live.channels()).single.health.enabled, isFalse);
    },
  );
}

void _cancelledUpdateTest() {
  test(
    'cancelled custom-source update is rechecked even if the old URI was responding recently',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.close);
      final old = (await LiveRepository(
        f.db,
        DocumentClient(f.http),
      ).channels()).single;
      await f.health.record(
        old,
        LiveHealth(
          availability: LiveAvailability.responding,
          preferredUrl: '${old.urls.single}',
        ),
      );
      final changed = LiveChannel(
        id: old.id,
        listId: 'custom',
        name: old.name,
        urls: [f.server.baseUri.resolve('new')],
      );
      final preflight = ChannelPreflight(
        LiveAuditDefaults(() async => '{"passedOnly":true,"results":[]}'),
        f.health,
        f.probe,
      );
      final token = CancellationToken()..cancel();
      await f.db.write('INSERT INTO app_meta VALUES(?,?)', [
        'live_state:broken',
        '{',
      ]);
      await expectLater(
        preflight.refresh([changed], token),
        throwsA(isA<RequestCancelled>()),
      );
      await preflight.refresh([changed], CancellationToken());
      final rows = await f.db.rows('SELECT value FROM app_meta WHERE key=?', [
        'live_state:${old.id}',
      ]);
      expect(
        LiveHealth.decode(rows.single['value'], changed.urls).enabled,
        isTrue,
      );
    },
  );
}

void _versionedProofTest() {
  test(
    'old cached and current URL versions keep independent proof for the same channel ID',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.close);
      final original = (await LiveRepository(
        f.db,
        DocumentClient(f.http),
      ).channels()).single;
      Map<String, Object?> proof(String path, bool passed) {
        final channel = LiveChannel(
          id: original.id,
          listId: original.listId,
          name: original.name,
          urls: [f.server.baseUri.resolve(path)],
          headerOrigin: f.list,
        );
        return {
          'id': original.id,
          'requestSignature': channelProbeSignature(channel),
          'availability': passed ? 'responding' : 'unavailable',
          'checkedAt': 1000,
          'verifiedIndices': passed ? [0] : <int>[],
          'preferredIndex': passed ? 0 : null,
        };
      }

      final defaults = LiveAuditDefaults(
        () async => jsonEncode({
          'passedOnly': true,
          'managedListIds': [original.listId],
          'results': [proof('ok', true), proof('bad', false)],
        }),
      );
      final live = LiveRepository(
        f.db,
        DocumentClient(f.http),
        defaults: defaults,
      );
      await live.importText('TV', f.list, f.playlist('ok'), verify: false);
      expect((await live.channels()).single.health.enabled, isTrue);
      await live.importText('TV', f.list, f.playlist('bad'), verify: false);
      expect((await live.channels()).single.health.enabled, isFalse);
      await live.importText('TV', f.list, f.playlist('ok'), verify: false);
      expect((await live.channels()).single.health.enabled, isTrue);
    },
  );
}

final class _Fixture {
  final db = AppDatabase.memory();
  final http = MediaHttpClient(allowPrivateNetworks: true);
  late final health = LiveHealthRepository(db);
  late final probe = LiveProbe(http, health);
  late ChannelPreflight preflight;
  late HttpTestServer server;
  final list = Uri.parse('https://list.test/a');
  Completer<void>? block, entered;
  bool fail = false;
  String playlist(String path) => 'One,${server.baseUri}$path';
  static Future<_Fixture> create() async {
    final f = _Fixture();
    f.server = await HttpTestServer.start((r) async {
      if (f.block != null) {
        if (!f.entered!.isCompleted) f.entered!.complete();
        await f.block!.future;
      }
      if (f.fail || r.uri.path == '/bad') {
        r.response.statusCode = 404;
        return;
      }
      r.response.add(List.filled(188, 0x47));
    });
    final raw = LiveRepository(f.db, DocumentClient(f.http));
    await raw.importText('TV', f.list, f.playlist('ok'));
    final c = (await raw.channels()).single;
    final defaults = LiveAuditDefaults(
      () async => jsonEncode({
        'passedOnly': true,
        'managedListIds': [stableId('${f.list}')],
        'results': [
          {
            'id': c.id,
            'signature': c.urls.join('|'),
            'requestSignature': channelProbeSignature(c),
            'availability': 'responding',
            'checkedAt': DateTime.now().millisecondsSinceEpoch - 1000,
            'preferredUrl': '${c.urls.single}',
            'verifiedUrls': ['${c.urls.single}'],
            'languages': <String>[],
          },
        ],
      }),
    );
    f.preflight = ChannelPreflight(defaults, f.health, f.probe);
    return f;
  }

  LiveRepository repository() => LiveRepository(
    db,
    DocumentClient(http),
    defaults: preflight.defaults,
    verifyUpdates: preflight.refresh,
  );
  Future<void> close() async {
    if (block != null && !block!.isCompleted) block!.complete();
    await probe.close();
    http.close();
    await server.close();
    await db.close();
  }
}
