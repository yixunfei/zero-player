import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import 'package:zero_player/features/sources/application/source_curation.dart';
import 'package:zero_player/features/sources/data/source_preferences.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/sources/domain/source_diagnostics.dart';
import 'package:zero_player/features/sources/domain/source_order.dart';

void main() {
  test(
    'curation enables successes and disables failures pending the next check',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final repo = SourceRepository(db);
      final rows = <Map<String, Object?>>[];
      for (final state in [
        'available',
        'unavailable',
        'inconclusive',
        'missingDomain',
      ]) {
        final url = Uri.parse('https://$state.test/api');
        await repo.saveManual(state, url, enabled: state != 'available');
        rows.add({
          'url': url.toString(),
          'kind': 'cms',
          'name': state,
          ...SourceDiagnostics(
            state: state,
            checkedAt: DateTime(2026, 10, 28),
          ).toJson(),
        });
      }
      final report = {'checkedAt': 'fixture-v1', 'results': rows};
      await SourceCuration(repo).apply(report);
      final all = {
        for (final source in await repo.all(includeSuppressed: true))
          source.name: source,
      };
      expect(all['available']!.enabled, isTrue);
      expect(all['inconclusive']!.enabled, isFalse);
      expect(all['inconclusive']!.diagnostics!.possiblyInvalid, isTrue);
      expect(all['unavailable']!.enabled, isFalse);
      expect(all['unavailable']!.suppressed, isFalse);
      expect(all['missingDomain']!.enabled, isFalse);
      expect(all['missingDomain']!.suppressed, isFalse);
      await repo.setEnabled(all['unavailable']!.id, true);
      await SourceCuration(repo).apply(report);
      expect((await repo.find(all['unavailable']!.id))!.enabled, isTrue);
    },
  );
  test(
    'default favorites are idempotent, cancel persists, and backup restores choices',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final repo = SourceRepository(db);
      for (final host in [
        'kanju3.com',
        'wu5mv.com',
        '360zy.com',
        'other.test',
      ]) {
        await repo.saveManual(host, Uri.https(host, '/'));
      }
      final prefs = SourcePreferences(db);
      await prefs.seedDefaults(await repo.all());
      var all = await repo.all();
      expect(all.where((s) => s.favorite), hasLength(3));
      final one = all.firstWhere((s) => s.favorite);
      await repo.favorite(one.id, false);
      await prefs.seedDefaults(await repo.all());
      expect((await repo.find(one.id))!.favorite, isFalse);
      all = (await repo.all())..sort(compareRecommendedSources);
      expect(all.take(2).every((s) => s.favorite), isTrue);
      final backup = BackupService(db);
      final payload = await backup.export();
      await repo.favorite(one.id, true);
      await backup.restore(await backup.preview(payload));
      expect((await repo.find(one.id))!.favorite, isFalse);
      final invalid = jsonDecode(payload) as Map;
      (invalid['tables']['app_meta'] as List).first['value'] = 'yes';
      await expectLater(
        backup.preview(jsonEncode(invalid)),
        throwsFormatException,
      );
    },
  );
}
