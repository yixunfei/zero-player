import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/application/builtin_sources.dart';
import 'package:zero_player/features/sources/application/source_probe.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';

/// Explicit maintenance only; never run as part of the regular test suite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'audit builtins and current source catalog',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      final repository = SourceRepository(db);
      final probe = SourceProbe(repository, DocumentClient(http));
      try {
        await BuiltinSources(repository).initialize();
        final builtins = (await repository.all(
          includeSuppressed: true,
        )).map((s) => s.id).toSet();
        const currentPath = String.fromEnvironment('SOURCE_DATABASE');
        if (currentPath.isNotEmpty) {
          await _includeCurrent(repository, File(currentPath));
        }
        const retry = bool.fromEnvironment('RETRY_INCONCLUSIVE');
        final sources = (await repository.all(includeSuppressed: true))
            .where(
              (source) =>
                  !retry ||
                  source.diagnostics == null ||
                  source.diagnostics?.state == 'inconclusive',
            )
            .toList();
        var completed = 0;
        probe.addListener(() {
          if (probe.results.length >= completed + 10) {
            completed = probe.results.length;
            // ignore: avoid_print
            print('已核查 $completed / ${sources.length}');
          }
        });
        await probe.run(sources, concurrency: 6);
        final rows = [
          for (final source in await repository.all(includeSuppressed: true))
            if (source.diagnostics != null)
              {
                'id': source.id,
                'url': source.endpoint.toString(),
                'kind': source.kind,
                'name': source.displayName,
                'siteTitle': source.siteTitle,
                'homepage': source.homepage?.toString(),
                'builtin': builtins.contains(source.id),
                ...source.diagnostics!.toJson(),
              },
        ];
        final report = {
          'checkedAt': DateTime.now().toUtc().toIso8601String(),
          'scope': 'Local machine API/DNS/TCP only; not media playback',
          'results': rows,
        };
        await Directory('artifacts').create(recursive: true);
        await File(
          'artifacts/source-audit-2026-10-28.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        await File('assets/source_audit.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            ...report,
            'results': rows.where((row) => row['builtin'] == true).toList(),
          }),
        );
        // ignore: avoid_print
        print({
          for (final state in [
            'available',
            'unavailable',
            'inconclusive',
            'missingDomain',
          ])
            state: rows.where((row) => row['state'] == state).length,
        });
      } finally {
        probe.dispose();
        http.close();
        await db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Future<void> _includeCurrent(SourceRepository target, File file) async {
  if (!await file.exists()) throw StateError('Source database does not exist');
  final current = AppDatabase(file);
  try {
    for (final source in await SourceRepository(
      current,
    ).all(includeSuppressed: true)) {
      await target.saveManual(
        source.name,
        source.endpoint,
        kind: source.kind,
        classification: source.classification,
        enabled: source.enabled,
        headers: source.headers,
      );
    }
  } finally {
    await current.close();
  }
}
