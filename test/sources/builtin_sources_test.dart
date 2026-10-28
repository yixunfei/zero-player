import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/application/builtin_sources.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('restore reuses an equivalent manual source identity', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final repository = SourceRepository(db);
    final report =
        jsonDecode(await rootBundle.loadString('assets/source_audit.json'))
            as Map;
    final uri = Uri.parse(
      (report['results'] as List).firstWhere(
            (item) => item['state'] == 'available' && item['kind'] == 'cms',
          )['url']
          as String,
    );
    final equivalent = uri.replace(
      queryParameters: {...uri.queryParameters, 'at': 'json'},
    );
    final id = await repository.saveManual('我的接口', equivalent);
    final builtins = BuiltinSources(repository);
    await builtins.initialize();
    await repository.batch([id], enabled: false, suppressed: true);
    await builtins.initialize(restore: true);
    expect((await repository.find(id))!.available, isTrue);
    expect((await repository.find(id))!.name, '我的接口');
  });
  test(
    'prechecked defaults apply once, preserve choices and restore explicitly',
    () async {
      final db = AppDatabase.memory();
      final repository = SourceRepository(db);
      try {
        final builtins = BuiltinSources(repository);
        await builtins.initialize();
        final all = await repository.all();
        expect(all, isNotEmpty);
        final report =
            jsonDecode(await rootBundle.loadString('assets/source_audit.json'))
                as Map;
        final defaults = {
          for (final result in report['results'] as List)
            result['url']: !{
              'unavailable',
              'missingDomain',
              'inconclusive',
            }.contains(result['state']),
        };
        expect(all.length, lessThanOrEqualTo(defaults.length));
        expect(all.any((s) => !s.enabled), isTrue);
        for (final source in all) {
          if (defaults.containsKey(source.endpoint.toString())) {
            if (defaults[source.endpoint.toString()] == false) {
              expect(source.enabled, isFalse);
            } else if (source.classification != 'adult') {
              expect(source.enabled, isTrue);
            }
          } else {
            expect(source.enabled, source.classification != 'adult');
          }
        }
        final selected = all.firstWhere((s) => s.enabled);
        await repository.batch([selected.id], enabled: false, suppressed: true);
        await builtins.initialize();
        expect((await repository.find(selected.id))!.suppressed, isTrue);
        await builtins.initialize(restore: true);
        expect((await repository.find(selected.id))!.available, isTrue);
      } finally {
        await db.close();
      }
    },
  );
}
