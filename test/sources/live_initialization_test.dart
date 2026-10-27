import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/application/builtin_live_sources.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/sources/application/builtin_sources.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import '../../test_support/http_test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  _refreshRaceTest();
  _backupHeadersTest();
  test(
    'builtin expansion preserves old overrides and restores removed live lists explicitly',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
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
        final live = LiveRepository(db, DocumentClient(http));
        final builtinLive = BuiltinLiveSources(live);
        await builtinLive.initialize();
        final lists = await live.lists();
        expect(lists.length, 11);
        expect(
          lists.map((r) => r['url']),
          containsAll([
            'https://m3u.ibert.me/cn.m3u',
            'https://raw.githubusercontent.com/fanmingming/live/main/tv/m3u/index.m3u',
            'https://raw.githubusercontent.com/ssili126/tv/main/itvlist.m3u',
          ]),
        );
        await live.removeList(lists.first['id'] as String);
        await builtinLive.initialize();
        expect((await live.lists()).length, 10);
        await builtinLive.initialize(restore: true);
        expect((await live.lists()).length, 11);
      } finally {
        http.close();
        await db.close();
      }
    },
  );
  test(
    'invalid or empty refresh cannot erase an existing live snapshot',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      try {
        final live = LiveRepository(db, DocumentClient(http));
        final uri = Uri.parse('https://tv.test/list');
        await live.importText('TV', uri, 'CCTV1,https://media.test/live.m3u8');
        await expectLater(
          live.importText('TV', uri, '#EXTM3U'),
          throwsFormatException,
        );
        await expectLater(
          live.importText('TV', uri, '<html>challenge</html>'),
          throwsFormatException,
        );
        expect((await live.channels()).single.name, 'CCTV1');
      } finally {
        http.close();
        await db.close();
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
    final http = MediaHttpClient();
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
      final http = MediaHttpClient();
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
