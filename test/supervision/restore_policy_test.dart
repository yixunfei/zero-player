import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';

void main() {
  test(
    'restore publishes changed classifications after cache rebuild',
    () async {
      final root = await Directory.systemTemp.createTemp('restore-policy-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      try {
        await services.supervision.load();
        await services.settings.load();
        final id = await services.sources.saveManual(
          'ordinary',
          Uri.parse('https://example.org/api'),
        );
        final source = (await services.sources.find(id))!;
        expect(services.contentPolicy.sourceAllowed(source), isTrue);
        final exported = jsonDecode(await services.backup.export()) as Map;
        exported['tables']['sources'][0]['classification'] = 'adult';
        final preview = await services.backup.preview(jsonEncode(exported));
        final observed = <bool>[];
        services.contentPolicy.addListener(() {
          observed.add(services.contentPolicy.sourceAllowed(source));
        });
        await services.restoreBackup(preview);
        expect(services.settings.value.filterAdult, isTrue);
        expect(observed, [false]);
      } finally {
        await services.close();
        await root.delete(recursive: true);
      }
    },
  );
}
