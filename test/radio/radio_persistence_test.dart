import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/radio/data/radio_repository.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import '../../test_support/http_test_server.dart';

String _list(String name) =>
    '#EXTM3U\n#EXTINF:-1 group-title="广播",$name\nhttps://media.test/$name.mp3\n';

void main() {
  group('persistence', _persistenceTests);
  group('refresh ordering', _raceTests);
}

void _persistenceTests() {
  late Directory root;
  late AppDatabase db;
  late MediaHttpClient http;
  late HttpTestServer server;
  late RadioRepository repository;
  var payload = _list('原电台');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('radio-snapshot-');
    db = AppDatabase.memory();
    http = MediaHttpClient();
    payload = _list('原电台');
    server = await HttpTestServer.start(
      (request) => request.response.write(payload),
    );
    repository = RadioRepository(
      db,
      DocumentClient(http),
      source: server.baseUri,
      snapshotDirectory: root,
    );
  });
  tearDown(() async {
    await repository.close();
    http.close();
    await server.close();
    await db.close();
    await root.delete(recursive: true);
  });

  test(
    'bad refresh preserves both database and disk success, then disk restores missing cache',
    () async {
      final initial = await repository.load();
      final subscription = (await repository.subscriptions()).single;
      final saved = repository.snapshots.file(subscription)!;
      final bytes = await saved.readAsString();
      payload = '<html>error</html>';
      final failed = await repository.load(refresh: true);
      expect(failed.notice, contains('更新失败'));
      expect(failed.stations.single.id, initial.stations.single.id);
      expect(await saved.readAsString(), bytes);
      await db.write('DELETE FROM app_meta WHERE key=?', [
        'radio_snapshot:${server.baseUri}',
      ]);
      final requests = server.calls['/'];
      expect(
        (await repository.load()).stations.single.id,
        initial.stations.single.id,
      );
      expect(server.calls['/'], requests);
    },
  );
  test(
    'favorites, duplicate subscriptions and disabled state persist through backup',
    () async {
      final initial = await repository.load();
      await repository.favorite(initial.stations.single, true);
      await repository.saveSubscription('订阅', server.baseUri);
      final sub = (await repository.subscriptions()).single;
      await repository.setEnabled(sub.id, false);
      await repository.saveSubscription(
        '新名称',
        server.baseUri.replace(fragment: 'label'),
      );
      expect(await repository.subscriptions(), hasLength(1));
      expect((await repository.subscriptions()).single.enabled, isFalse);
      expect((await repository.load()).stations, isEmpty);
      final backup = BackupService(db);
      final snapshot = await backup.preview(await backup.export());
      await repository.setEnabled(sub.id, true);
      await repository.favorite(initial.stations.single, false);
      await backup.restore(snapshot);
      expect((await repository.subscriptions()).single.enabled, isFalse);
      await repository.setEnabled(sub.id, true);
      final reopened = RadioRepository(
        db,
        DocumentClient(http),
        source: server.baseUri,
        snapshotDirectory: root,
      );
      addTearDown(reopened.close);
      expect((await reopened.load()).stations.single.favorite, isTrue);
      await repository.removeSubscription(sub.id);
      expect(await repository.subscriptions(), isEmpty);
      expect((await repository.load()).stations, isEmpty);
      await repository.saveSubscription('重新添加', server.baseUri);
      expect((await repository.load()).stations.single.favorite, isTrue);
    },
  );
}

void _raceTests() {
  test(
    'an older refresh response never overwrites a newer successful snapshot',
    () async {
      final blocked = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final server = await HttpTestServer.start((request) async {
        calls++;
        if (calls == 1) {
          blocked.complete();
          await release.future;
          request.response.write(_list('旧'));
        } else {
          request.response.write(_list('新'));
        }
      });
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      final repo = RadioRepository(
        db,
        DocumentClient(http),
        source: server.baseUri,
      );
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await repo.close();
        http.close();
        await server.close();
        await db.close();
      });
      final old = repo.load(refresh: true);
      await blocked.future;
      expect((await repo.load(refresh: true)).stations.single.name, '新');
      release.complete();
      await old;
      expect((await repo.load()).stations.single.name, '新');
      final token = CancellationToken()..cancel();
      await expectLater(
        repo.load(refresh: true, cancellation: token),
        throwsA(isA<RequestCancelled>()),
      );
      expect((await repo.load()).stations.single.name, '新');
    },
  );
}
