import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/application/builtin_sources.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
            jsonDecode(
                  await rootBundle.loadString('assets/source_precheck.json'),
                )
                as Map;
        final defaults = {
          for (final result in report['results'] as List)
            result['url']: result['defaultEnabled'],
        };
        expect(defaults.length, all.length);
        expect(all.any((s) => !s.enabled), isTrue);
        for (final source in all) {
          expect(source.enabled, defaults[source.endpoint.toString()]);
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
