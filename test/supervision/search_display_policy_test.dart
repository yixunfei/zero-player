import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/library/data/history_repository.dart';
import 'package:zero_player/features/search/application/search_controller.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/supervision_fixture.dart';

void main() {
  test(
    'tightening policy removes cached search entries and website diagnostics together',
    () async {
      final f = SupervisionFixture();
      await f.load();
      await f.settings.update({'filterAdult': false});
      final restricted = await f.sources.saveManual(
        '森林',
        Uri.parse('https://slapibf.com/api'),
      );
      final ordinary = await f.sources.saveManual(
        '普通频道',
        Uri.parse('https://ordinary.test/api'),
      );
      final http = MediaHttpClient();
      final search = SearchController(
        f.sources,
        DocumentClient(http),
        HistoryRepository(f.db, policy: f.policy),
      );
      addTearDown(() async {
        search.dispose();
        http.close();
        await f.close();
      });
      search.items.addAll([
        CatalogItem(sourceId: restricted, id: '1', title: '受限条目'),
        CatalogItem(sourceId: ordinary, id: '2', title: '普通条目'),
      ]);
      search.statuses.addAll({restricted: '1 条结果', ordinary: '1 条结果'});
      search.sourceNames.addAll({
        restricted: '森林 · slapibf.com',
        ordinary: '普通频道',
      });
      search.latencies[restricted] = 100;
      search.failedSources.add(restricted);
      search.preferredSourceId = restricted;
      expect(search.groups.length, 2);
      await f.configure();
      expect(search.items.map((i) => i.title), ['普通条目']);
      expect(search.groups.length, 1);
      expect(search.statuses.containsKey(restricted), isFalse);
      expect(search.sourceNames.containsKey(restricted), isFalse);
      expect(search.latencies.containsKey(restricted), isFalse);
      expect(search.failedSources, isNot(contains(restricted)));
      expect(search.preferredSourceId, isNull);
    },
  );

  test(
    'personal backup with complete site URLs requires its own one-operation grant',
    () async {
      final f = SupervisionFixture();
      addTearDown(f.close);
      await f.configure();
      final backup = BackupService(
        f.db,
        authorizeExport: () => f.guard.require(SensitiveOperation.export),
      );
      await expectLater(backup.export(), throwsFormatException);
      await expectLater(
        f.authorized(SensitiveOperation.channels, backup.export),
        throwsFormatException,
      );
      expect(
        await f.authorized(SensitiveOperation.export, backup.export),
        contains('ZeroPlayer-Backup'),
      );
      await expectLater(backup.export(), throwsFormatException);
    },
  );
}
