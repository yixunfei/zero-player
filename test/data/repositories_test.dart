import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/sources/domain/source_catalog.dart';

void main() {
  late AppDatabase db;
  late SourceRepository sources;
  setUp(() {
    db = AppDatabase.memory();
    sources = SourceRepository(db);
  });
  tearDown(() => db.close());
  test(
    'subscription shared membership and user overrides survive refresh',
    () async {
      final a = Uri.parse('https://example.org/a.json');
      final b = Uri.parse('https://example.org/b.json');
      final source = SourceCandidate(
        name: 'remote',
        endpoint: Uri.parse('https://media.example/api'),
        kind: SourceKind.cms,
        requestedEnabled: true,
      );
      await sources.applySubscription(a, 'A', '{}', [source]);
      await sources.applySubscription(b, 'B', '{}', [source]);
      var all = await sources.all();
      expect(all.single.enabled, isFalse);
      await sources.setEnabled(all.single.id, true);
      await sources.applySubscription(a, 'A', '{}', []);
      all = await sources.all();
      expect(all.single.enabled, isTrue);
      await sources.suppress(all.single.id, true);
      await sources.applySubscription(b, 'B', '{}', [source]);
      expect(await sources.all(), isEmpty);
      await sources.suppress(all.single.id, false);
      expect((await sources.all()).single.enabled, isTrue);
    },
  );
  test('backup validates JSON settings before replacing any data', () async {
    final id = await sources.saveManual(
      'kept',
      Uri.parse('https://example.org/api'),
    );
    final backup = BackupService(db);
    final data = jsonDecode(await backup.export()) as Map;
    data['tables']['settings'] = [
      {'key': 'cacheMiB', 'value': '"invalid"'},
    ];
    await expectLater(backup.preview(jsonEncode(data)), throwsFormatException);
    expect((await sources.find(id))!.name, 'kept');
  });
  test('foreign-key failure rolls back a complete restore', () async {
    final id = await sources.saveManual(
      'kept',
      Uri.parse('https://example.org/api'),
    );
    final backup = BackupService(db);
    final data = jsonDecode(await backup.export()) as Map;
    data['tables']['source_overrides'][0]['source_id'] = 'missing';
    final preview = await backup.preview(jsonEncode(data));
    await expectLater(backup.restore(preview), throwsA(anything));
    expect((await sources.find(id))!.name, 'kept');
  });
  test('backup restores settings and source headers transactionally', () async {
    final id = await sources.saveManual(
      'saved',
      Uri.parse('https://example.org/api'),
      headers: {'X-Test': 'private'},
    );
    final backup = BackupService(db);
    final preview = await backup.preview(await backup.export());
    await sources.suppress(id, true);
    await backup.restore(preview);
    expect((await sources.all()).single.headers['X-Test'], 'private');
  });
}
