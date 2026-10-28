import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';
import 'package:zero_player/features/settings/presentation/adult_filter_setting.dart';
import 'package:zero_player/features/supervision/application/content_policy.dart';
import 'package:zero_player/features/supervision/application/supervision_controller.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/supervision_fixture.dart';

void main() {
  late SupervisionFixture f;
  late String id;
  setUp(() async {
    f = SupervisionFixture();
    await f.load();
    await f.settings.update({'filterAdult': false});
    id = await f.sources.saveManual(
      '受限来源',
      Uri.parse('https://fixture.test/api'),
      classification: 'adult',
    );
  });
  tearDown(() => f.close());

  test(
    'supervision overrides a disabled preference across content boundaries',
    () async {
      final source = (await f.sources.find(id))!;
      final item = CatalogItem(sourceId: id, id: 'item', title: '普通标题');
      final channel = LiveChannel(
        id: 'c',
        listId: 'l',
        name: '频道',
        group: '成人',
        urls: [Uri.parse('https://fixture.test/media')],
      );
      expect(f.policy.sourceAllowed(source), isTrue);
      await f.configure();
      expect(f.settings.value.filterAdult, isFalse);
      expect(f.policy.filterAdult, isTrue);
      expect(f.policy.sourceAllowed(source), isFalse);
      expect(f.policy.itemAllowed(item), isFalse);
      expect(f.policy.channelAllowed(channel), isFalse);
      expect(f.policy.channelAllowed(channel, radio: true), isFalse);
      await f.authorized(
        SensitiveOperation.channels,
        () => f.sources.setEnabled(id, true),
      );
      expect((await f.sources.find(id))!.enabled, isTrue);
      expect(f.policy.sourceAllowed(source), isFalse);
    },
  );

  test(
    'restart and authorized restore cannot weaken mandatory filtering',
    () async {
      final backup = BackupService(
        f.db,
        authorize: () => f.guard.require(SensitiveOperation.restore),
      );
      final preview = await backup.preview(await backup.export());
      await f.configure();
      await f.authorized(
        SensitiveOperation.restore,
        () => backup.restore(preview),
      );
      await f.settings.load();
      expect(f.settings.value.filterAdult, isFalse);
      expect(f.policy.filterAdult, isTrue);
      final restarted = SupervisionController(f.db, hasher: f.hasher);
      await restarted.load();
      final policy = ContentPolicy(f.settings, restarted);
      expect(policy.sourceAllowed((await f.sources.find(id))!), isFalse);
      policy.dispose();
      await restarted.close();
    },
  );

  testWidgets(
    'switch reflects mandatory filtering and updates after supervision changes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdultFilterSetting(policy: f.policy)),
        ),
      );
      SwitchListTile toggle() => tester.widget(find.byType(SwitchListTile));
      expect(toggle().value, isFalse);
      await tester.runAsync(f.configure);
      await tester.pump();
      expect(toggle().value, isTrue);
      expect(toggle().onChanged, isNull);
      await tester.runAsync(
        () => f.authorized(
          SensitiveOperation.supervision,
          () => f.guard.setEnabled(false),
        ),
      );
      await tester.pump();
      expect(toggle().value, isFalse);
      expect(toggle().onChanged, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
