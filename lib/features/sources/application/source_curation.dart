import 'dart:convert';
import 'package:flutter/services.dart';
import '../data/source_repository.dart';
import '../data/source_identity_store.dart';
import '../data/source_diagnostics_store.dart';
import '../domain/source_diagnostics.dart';

final class SourceCuration {
  const SourceCuration(this.repository);
  final SourceRepository repository;

  Future<void> initialize({bool restore = false}) async {
    final report =
        jsonDecode(await rootBundle.loadString('assets/source_audit.json'))
            as Map;
    await apply(report, restore: restore);
  }

  Future<void> apply(Map report, {bool restore = false}) async {
    final version = '${report['checkedAt']}:automatic-v2';
    final previous = await repository.db.rows(
      "SELECT value FROM app_meta WHERE key='source_curation'",
    );
    if (!restore && previous.firstOrNull?['value'] == version) return;
    final identities = SourceIdentityStore(repository.db);
    for (final row in (report['results'] as List).cast<Map>()) {
      final endpoint = Uri.parse(row['url'] as String);
      final id = await identities.resolve(row['kind'] as String, endpoint);
      final source = await repository.find(id);
      if (source == null) continue;
      final recorded = SourceDiagnostics.decode(jsonEncode(row));
      if (recorded == null) continue;
      final newer = source.diagnostics;
      final result =
          newer != null && newer.checkedAt.isAfter(recorded.checkedAt)
          ? newer
          : recorded;
      final title = row['siteTitle'] as String?;
      if (title != null) {
        await repository.metadata(
          id,
          title: title,
          homepage: _homepage(row['homepage']),
        );
      }
      final name = row['name'] as String?;
      if (name != null && name.isNotEmpty && name != endpoint.host) {
        await repository.db.write(
          'UPDATE sources SET name=? WHERE id=? AND (name=? OR name=?)',
          [name, id, endpoint.host, endpoint.toString()],
        );
      }
      await SourceDiagnosticsStore(
        repository.db,
      ).save(id, result, applyPolicy: true);
      if (result.state == 'available' &&
          (source.checkedAt == null ||
              source.checkedAt!.isBefore(result.checkedAt))) {
        await repository.health(id, null, latencyMs: _latency(result));
      }
    }
    await repository.db.write(
      "INSERT OR REPLACE INTO app_meta VALUES('source_curation',?)",
      [version],
    );
  }

  int? _latency(SourceDiagnostics result) =>
      result.requests.firstOrNull?['elapsedMs'] as int?;

  Uri? _homepage(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value);
    return uri != null &&
            uri.hasAuthority &&
            (uri.scheme == 'https' || uri.scheme == 'http')
        ? uri
        : null;
  }
}
