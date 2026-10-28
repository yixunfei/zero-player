import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/sources/data/source_diagnostics_store.dart';
import 'package:zero_player/features/sources/domain/source_catalog.dart';
import 'package:zero_player/features/sources/domain/source_diagnostics.dart';
import 'package:zero_player/features/sources/domain/source_duplicates.dart';
import 'package:zero_player/features/sources/domain/source_order.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';

final _origin = Uri.parse('https://catalog.test/list');
final _candidates = [
  for (final scheme in ['http', 'https'])
    SourceCandidate(
      name: '同名渠道',
      endpoint: Uri.parse('$scheme://cms.test/api'),
      kind: SourceKind.cms,
      requestedEnabled: true,
    ),
];

void main() {
  test(
    'same names keep healthy endpoint and preserve history favorites and default',
    _dedupLifecycle,
  );
  test(
    'restoring an alternate swaps the representative and refresh remains deduplicated',
    _restore,
  );
  test(
    'disable operation only touches confirmed still-invalid active rows',
    _disable,
  );
  test(
    'representation duplicates merge but credentials and generic titles stay distinct',
    _identities,
  );
  test('recommendation order stays stable after latency changes', () {
    VideoSource source(String id, int latency) => VideoSource(
      id: id,
      name: id,
      endpoint: Uri.https('$id.test'),
      latencyMs: latency,
    );
    expect(
      compareRecommendedSources(source('a', 999), source('b', 1)),
      lessThan(0),
    );
    expect(
      compareRecommendedSources(source('a', 1), source('b', 999)),
      lessThan(0),
    );
  });
}

Future<SourceRepository> _repository() async {
  final db = AppDatabase.memory();
  addTearDown(db.close);
  final repo = SourceRepository(db);
  await repo.applySubscription(
    _origin,
    'list',
    'snapshot',
    _candidates,
    enableNew: true,
    deduplicateSources: false,
  );
  return repo;
}

Future<void> _dedupLifecycle() async {
  final repo = await _repository();
  final all = await repo.all();
  final old = all.firstWhere((s) => s.endpoint.scheme == 'http');
  final keep = all.firstWhere((s) => s.endpoint.scheme == 'https');
  await SourceDiagnosticsStore(repo.db).save(
    old.id,
    SourceDiagnostics(state: 'unavailable', checkedAt: DateTime.now()),
  );
  await SourceDiagnosticsStore(repo.db).save(
    keep.id,
    SourceDiagnostics(state: 'available', checkedAt: DateTime.now()),
  );
  await repo.favorite(old.id, true);
  await repo.db.write('INSERT INTO settings VALUES(?,?)', [
    'homeChannel',
    jsonEncode(old.id),
  ]);
  await repo.db.write(
    '''INSERT INTO watch_history
    (id,source_id,remote_id,title,line_name,episode_label,position_ms,duration_ms,updated_at)
    VALUES(?,?,?,?,?,?,?,?,?)''',
    ['history', old.id, 'film', 'film', 'line', '1', 50, 100, 1],
  );
  final result = await repo.deduplicate();
  expect(result, {old.id: keep.id});
  expect((await repo.all()).single.id, keep.id);
  expect((await repo.find(keep.id))!.favorite, isTrue);
  expect((await repo.find(old.id))!.suppressed, isTrue);
  expect(await repo.all(includeSuppressed: true), hasLength(2));
  expect(await repo.preferredId(old.id), keep.id);
  expect(
    (await repo.db.rows('SELECT value FROM settings')).single['value'],
    jsonEncode(keep.id),
  );
  expect(
    (await repo.db.rows(
      'SELECT source_id FROM watch_history',
    )).single['source_id'],
    old.id,
  );
  expect(await repo.deduplicate(), isEmpty);
}

Future<void> _restore() async {
  final repo = await _repository();
  await repo.deduplicate();
  final current = (await repo.all()).single;
  final removed = (await repo.all(
    includeSuppressed: true,
  )).firstWhere((s) => s.suppressed);
  await repo.suppress(removed.id, false);
  expect((await repo.all()).single.id, removed.id);
  expect(await repo.preferredId(current.id), removed.id);
  expect(await repo.preferredId(removed.id), removed.id);
  await repo.applySubscription(
    _origin,
    'list',
    'snapshot',
    _candidates,
    enableNew: true,
  );
  expect((await repo.all()).single.id, removed.id);
  expect((await repo.find(current.id))!.suppressed, isTrue);
}

Future<void> _disable() async {
  final db = AppDatabase.memory();
  addTearDown(db.close);
  final repo = SourceRepository(db);
  final ids = <String>[];
  for (var i = 0; i < 4; i++) {
    final id = await repo.saveManual(
      '渠道$i',
      Uri.https('source$i.test', '/api'),
    );
    ids.add(id);
    if (i != 3) {
      await SourceDiagnosticsStore(db).save(
        id,
        SourceDiagnostics(state: 'inconclusive', checkedAt: DateTime(2000)),
      );
    }
  }
  await repo.health(ids[1], null);
  await repo.suppress(ids[2], true);
  expect(await repo.disablePossiblyInvalid(ids), 1);
  expect((await repo.find(ids[0]))!.enabled, isFalse);
  expect((await repo.find(ids[1]))!.enabled, isTrue);
  expect((await repo.find(ids[2]))!.enabled, isTrue);
  expect((await repo.find(ids[3]))!.enabled, isTrue);
  expect((await repo.find(ids[0]))!.suppressed, isFalse);
}

void _identities() {
  VideoSource source(String id, String name, String url, {String? title}) =>
      VideoSource(
        id: id,
        name: name,
        endpoint: Uri.parse(url),
        siteTitle: title,
      );
  expect(
    duplicateSourceGroups([
      source('a', '甲', 'https://cms.test/api/at/xml/?b=2&a=1'),
      source('b', '乙', 'https://cms.test/api?a=1&b=2'),
    ]).single,
    hasLength(2),
  );
  expect(
    duplicateSourceGroups([
      source('a', '甲', 'https://cms.test/api?token=a'),
      source('b', '乙', 'https://cms.test/api?token=b'),
      source('c', 'one.test', 'https://one.test/api', title: 'welcome'),
      source('d', 'two.test', 'https://two.test/api', title: 'welcome'),
    ]),
    isEmpty,
  );
}
