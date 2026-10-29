import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/library/data/history_repository.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import '../../test_support/supervision_fixture.dart';

void main() {
  test(
    'restored history retains content labels and applies current policy',
    () async {
      final original = SupervisionFixture(), restored = SupervisionFixture();
      try {
        await original.load();
        await restored.load();
        final source = await original.sources.saveManual(
          '普通来源',
          Uri.parse('https://example.org/api'),
        );
        final history = HistoryRepository(original.db);
        final episode = Episode(
          '1',
          Uri.parse('https://example.org/movie.mp4'),
        );
        for (final (id, category) in [('normal', '剧情'), ('adult', '韩国伦理')]) {
          await history.save(
            CatalogItem(
              sourceId: source,
              id: id,
              title: '电影',
              category: category,
            ),
            PlayLine('main', [episode]),
            episode,
            const Duration(seconds: 10),
            const Duration(minutes: 2),
          );
        }
        final text = await BackupService(original.db).export();
        await restored.db.write('INSERT INTO app_meta(key,value) VALUES(?,?)', [
          'content_label:$source:normal',
          jsonEncode({'title': '旧标签', 'category': '成人'}),
        ]);
        final backup = BackupService(restored.db);
        await backup.restore(await backup.preview(text));
        await restored.settings.load();
        await restored.sources.all();
        final visible = HistoryRepository(restored.db, policy: restored.policy);
        expect((await visible.all()).map((e) => e.remoteId), ['normal']);
        await restored.configure();
        expect((await visible.recentWorks()).map((e) => e.remoteId), [
          'normal',
        ]);
        expect(
          (await restored.db.rows('SELECT id FROM watch_history')).length,
          2,
        );
      } finally {
        await original.close();
        await restored.close();
      }
    },
  );

  test('malformed history classification is rejected before restore', () async {
    final fixture = SupervisionFixture();
    try {
      await fixture.load();
      final backup = BackupService(fixture.db);
      final data = jsonDecode(await backup.export()) as Map;
      data['tables']['app_meta'] = [
        {
          'key': 'content_label:source:id',
          'value': '{"title":"电影","category":42}',
        },
      ];
      await expectLater(
        backup.preview(jsonEncode(data)),
        throwsFormatException,
      );
    } finally {
      await fixture.close();
    }
  });
}
