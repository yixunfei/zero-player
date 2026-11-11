import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/application/builtin_live_sources.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/data/live_audit_defaults.dart';
import 'package:zero_player/features/sources/application/builtin_sources.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import '../../test_support/http_test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  _refreshRaceTest();
  _backupHeadersTest();
  _builtinInitializationTest();
  _upgradeTest();
  _quarantineUpgradeTest();
  test(
    'invalid or empty refresh cannot erase an existing live snapshot',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      try {
        final live = LiveRepository(db, DocumentClient(http));
        final uri = Uri.parse('https://tv.test/list');
        await live.importText('TV', uri, 'CCTV1,https://media.test/live.m3u8');
        final saved = (await live.channels()).single;
        await expectLater(
          live.importText('TV', uri, '#EXTM3U'),
          throwsFormatException,
        );
        await expectLater(
          live.importText('TV', uri, '<html>challenge</html>'),
          throwsFormatException,
        );
        final retained = (await live.channels()).single;
        expect(retained.id, saved.id);
        expect(retained.name, 'CCTV-1 综合');
        expect(retained.urls, saved.urls);
      } finally {
        http.close();
        await db.close();
      }
    },
  );
}

void _builtinInitializationTest() {
  test(
    'builtin expansion preserves old overrides and restores removed live lists explicitly',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      try {
        final sources = SourceRepository(db);
        final builtins = BuiltinSources(sources);
        await builtins.initialize();
        final old = (await sources.all()).first;
        await sources.batch([old.id], enabled: false, suppressed: true);
        await db.write(
          "UPDATE app_meta SET value='1' WHERE key='builtin_sources'",
        );
        await builtins.initialize();
        expect((await sources.find(old.id))!.suppressed, isTrue);
        expect(
          (await sources.all()).map((s) => s.kind),
          containsAll(['kanju', 'macCmsHtml']),
        );
        final live = LiveRepository(
          db,
          DocumentClient(http),
          defaults: LiveAuditDefaults.bundled(),
        );
        final builtinLive = BuiltinLiveSources(live);
        final asset =
            jsonDecode(
                  await rootBundle.loadString('assets/live_candidates.json'),
                )
                as Map;
        final expected = (asset['lists'] as List)
            .map((row) => row['url'])
            .toSet();
        await builtinLive.initialize();
        final lists = await live.lists();
        expect(lists.map((r) => r['url']).toSet(), expected);
        expect(
          lists.every((r) => r['snapshot'] is String && r['enabled'] == 1),
          isTrue,
        );
        final precheck =
            jsonDecode(await rootBundle.loadString('assets/live_precheck.json'))
                as Map;
        final channels = await live.channels();
        expect(channels.length, precheck['channels']);
        expect(
          channels.every(
            (channel) =>
                channel.health.enabled && channel.playbackUrls.isNotEmpty,
          ),
          isTrue,
        );
        final urls = channels
            .expand((channel) => channel.playbackUrls)
            .toList();
        expect(urls.toSet().length, precheck['routes']);
        expect(urls.toSet().length, urls.length);
        await live.removeList(lists.first['id'] as String);
        await builtinLive.initialize();
        expect((await live.lists()).length, expected.length - 1);
        await builtinLive.initialize(restore: true);
        expect((await live.lists()).length, expected.length);
      } finally {
        http.close();
        await db.close();
      }
    },
  );
}

void _upgradeTest() {
  test(
    'upgrade retires legacy built-ins and replaces only managed snapshots',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      addTearDown(() async {
        http.close();
        await db.close();
      });
      final live = LiveRepository(db, DocumentClient(http));
      final builtin = BuiltinLiveSources(live);
      addTearDown(builtin.close);
      final catalog =
          jsonDecode(await rootBundle.loadString('assets/live_candidates.json'))
              as Map;
      final retired = Uri.parse((catalog['retired'] as List).first);
      final kept = Uri.parse((catalog['lists'] as List).first['url']);
      const old = 'OLD,https://test.example/media';
      await live.importText('Old', retired, old);
      await live.importText('Kept', kept, old);
      final own = Uri.parse('https://local.test/own');
      await live.importText('Own', own, old);
      final before = {
        for (final row in await live.lists()) row['url']: row['id'],
      };
      for (final uri in [retired, kept]) {
        await db.write('INSERT INTO app_meta VALUES(?,?)', [
          'builtin_live:${before['$uri']}',
          '1',
        ]);
      }
      await builtin.initialize();
      final after = {for (final row in await live.lists()) row['url']: row};
      expect(after['$retired']!['enabled'], 0);
      expect(after['$retired']!['snapshot'], old);
      expect(after['$kept']!['snapshot'], isNot(old));
      expect(after['$own']!['snapshot'], old);
      expect(after['$own']!['enabled'], 1);
      await live.setListEnabled(after['$retired']!['id'] as String, true);
      await builtin.initialize();
      final restored = (await live.lists()).firstWhere(
        (row) => row['url'] == '$retired',
      );
      expect(restored['enabled'], 1);
    },
  );
}

void _quarantineUpgradeTest() {
  test(
    'upgrade isolates confirmed wrong-content lists after legacy migration',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      final live = LiveRepository(db, DocumentClient(http));
      final builtin = BuiltinLiveSources(live);
      addTearDown(() async {
        await builtin.close();
        http.close();
        await db.close();
      });
      final catalog =
          jsonDecode(await rootBundle.loadString('assets/live_candidates.json'))
              as Map;
      final quarantined = (catalog['quarantined'] as List).cast<Map>();
      final retired = Uri.parse((catalog['retired'] as List).first);
      const old = 'CCTV-14,https://media.test/old.m3u8';
      for (final entry in quarantined) {
        await live.importText(entry['name'], Uri.parse(entry['url']), old);
      }
      await live.importText('Restored legacy', retired, old);
      await db.write('INSERT INTO app_meta VALUES(?,?)', [
        "builtin_live_retired:${catalog['version']}",
        '1',
      ]);

      await builtin.initialize(restore: true);

      final lists = {for (final row in await live.lists()) row['url']: row};
      expect(lists['$retired']!['enabled'], 1);
      for (final entry in quarantined) {
        final row = lists[entry['url']]!;
        expect(row['enabled'], 0);
        expect(row['snapshot'], old);
        expect(row['quarantine_reason'], entry['reason']);
        await expectLater(
          live.setListEnabled(row['id'] as String, true),
          throwsFormatException,
        );
        await expectLater(
          live.importText(entry['name'], Uri.parse(entry['url']), old),
          throwsFormatException,
        );
      }
      final allowed = (await live.channels()).expand((c) => c.entries);
      for (final entry in quarantined) {
        expect(
          allowed.map((c) => c.headerOrigin.toString()),
          isNot(contains(entry['url'])),
        );
      }
    },
  );
}

void _refreshRaceTest() {
  test('removing a list during refresh cannot resurrect it', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final server = await HttpTestServer.start((request) async {
      started.complete();
      await release.future;
      request.response.write('NEW,https://media.test/new.m3u8');
    });
    final db = AppDatabase.memory();
    final http = MediaHttpClient(allowPrivateNetworks: true);
    try {
      final live = LiveRepository(db, DocumentClient(http));
      await live.importText(
        'TV',
        server.baseUri,
        'OLD,https://media.test/old.m3u8',
      );
      final refresh = live.import('TV', server.baseUri, existingOnly: true);
      await started.future;
      await live.removeList((await live.lists()).single['id'] as String);
      release.complete();
      await refresh;
      expect(await live.lists(), isEmpty);
      expect(await live.channels(), isEmpty);
    } finally {
      if (!release.isCompleted) release.complete();
      http.close();
      await server.close();
      await db.close();
    }
  });
}

void _backupHeadersTest() {
  test(
    'backup restores subscription headers and rejects unrelated app metadata',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      try {
        final live = LiveRepository(db, DocumentClient(http));
        await live.importText(
          'TV',
          Uri.parse('https://tv.test/list'),
          'CCTV1,https://media.test/live.m3u8',
          headers: {'User-Agent': 'custom-player'},
        );
        final backup = BackupService(db);
        final exported = await backup.export();
        await db.write("DELETE FROM app_meta WHERE key GLOB 'live_headers:*'");
        await backup.restore(await backup.preview(exported));
        final row = (await db.rows(
          "SELECT value FROM app_meta WHERE key GLOB 'live_headers:*'",
        )).single;
        expect(jsonDecode(row['value'] as String), {
          'User-Agent': 'custom-player',
        });
        final invalid = jsonDecode(exported) as Map;
        invalid['tables']['app_meta'][0]['key'] = 'builtin_sources';
        await expectLater(
          backup.preview(jsonEncode(invalid)),
          throwsFormatException,
        );
      } finally {
        http.close();
        await db.close();
      }
    },
  );
}
