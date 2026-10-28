import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/live/domain/live_health.dart';
import 'package:zero_player/features/sources/data/source_diagnostics_store.dart';
import 'package:zero_player/features/sources/domain/source_diagnostics.dart';
import 'package:zero_player/features/sources/domain/source_catalog.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/supervision_fixture.dart';

late SupervisionFixture f;
late String id;

void main() {
  setUp(() async {
    f = SupervisionFixture();
    await f.load();
    id = await f.sources.saveManual(
      'ordinary',
      Uri.parse('https://example.org/api'),
      enabled: false,
    );
    await f.configure();
  });
  tearDown(() => f.close());
  _registerCases0();
  _registerCases1();
}

void _registerCases0() {
  test(
    'repository guards enable, restore, manual edits and adult-filter changes',
    () async {
      await expectLater(f.sources.setEnabled(id, true), throwsFormatException);
      await expectLater(
        f.sources.batch([id], enabled: true),
        throwsFormatException,
      );
      await expectLater(
        f.sources.batch([id], suppressed: false),
        throwsFormatException,
      );
      await expectLater(
        f.sources.saveManual('renamed', Uri.parse('https://example.org/api')),
        throwsFormatException,
      );
      await expectLater(
        f.settings.update({'filterAdult': false}),
        throwsFormatException,
      );
      await f.authorized(
        SensitiveOperation.channels,
        () => f.sources.setEnabled(id, true),
      );
      expect((await f.sources.find(id))!.enabled, isTrue);
      await f.sources.setEnabled(id, false);
      await expectLater(f.sources.setEnabled(id, true), throwsFormatException);
      await f.authorized(
        SensitiveOperation.settings,
        () => f.settings.update({'filterAdult': false}),
      );
      expect(f.settings.value.filterAdult, isFalse);
      await f.settings.update({'filterAdult': true});
    },
  );
  test(
    'successful diagnostics cannot automatically enable locked channels',
    () async {
      final store = SourceDiagnosticsStore(
        f.db,
        canEnable: f.sources.canEnable,
      );
      final result = SourceDiagnostics(state: 'available', checkedAt: f.now);
      await store.save(id, result, applyPolicy: true);
      expect((await f.sources.find(id))!.enabled, isFalse);
      await f.authorized(
        SensitiveOperation.channels,
        () => store.save(id, result, applyPolicy: true),
      );
      expect((await f.sources.find(id))!.enabled, isTrue);
    },
  );
}

void _registerCases1() {
  test(
    'subscription refresh adds candidates disabled without an active grant',
    () async {
      await f.sources.applySubscription(
        Uri.parse('https://example.org/list'),
        'list',
        '{}',
        [
          SourceCandidate(
            name: 'new',
            endpoint: Uri.parse('https://new.example.org/api'),
            kind: SourceKind.cms,
            requestedEnabled: true,
          ),
        ],
        enableNew: true,
      );
      final fresh = (await f.sources.all()).singleWhere((s) => s.name == 'new');
      expect(fresh.enabled, isFalse);
    },
  );
  test(
    'live restore and probe recovery respect the same operation grant',
    () async {
      final health = LiveHealthRepository(
        f.db,
        authorize: f.sources.authorize,
        canEnable: f.sources.canEnable,
      );
      final channel = LiveChannel(
        id: 'live-id',
        listId: 'list',
        name: 'news',
        urls: [Uri.parse('https://example.org/live')],
      );
      await health.setEnabled([channel.id], false);
      await expectLater(
        health.setEnabled([channel.id], true),
        throwsFormatException,
      );
      await expectLater(
        health.setRemoved([channel.id], false),
        throwsFormatException,
      );
      final result = LiveHealth(availability: LiveAvailability.responding);
      await health.record(channel, result, enableResponding: true);
      var state = (await f.db.rows('SELECT value FROM app_meta WHERE key=?', [
        'live_state:live-id',
      ])).single['value'];
      expect(state, contains('"enabled":false'));
      await f.authorized(
        SensitiveOperation.channels,
        () => health.record(channel, result, enableResponding: true),
      );
      state = (await f.db.rows('SELECT value FROM app_meta WHERE key=?', [
        'live_state:live-id',
      ])).single['value'];
      expect(state, contains('"enabled":true'));
    },
  );
}
