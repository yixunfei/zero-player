import 'dart:convert';
import 'package:flutter/services.dart';
import '../data/source_repository.dart';
import '../data/source_identity_store.dart';
import '../domain/source_catalog.dart';
import '../domain/video_source.dart';
import 'maccms_sources.dart';
import '../data/source_preferences.dart';
import 'source_curation.dart';

final class BuiltinSources {
  const BuiltinSources(this.repository);
  final SourceRepository repository;
  static final origin = Uri.parse(
    'https://github.com/LibreSpark/LibreTV/discussions/652#builtin',
  );

  Future<void> initialize({bool restore = false}) async {
    await _initializeOriginal(restore: restore);
    await MaccmsSources(repository).initialize(restore: restore);
    await SourceCuration(repository).initialize(restore: restore);
    await repository.applyVerifiedContentLabels();
    await SourcePreferences(
      repository.db,
    ).seedDefaults(await repository.all(includeSuppressed: true));
    await repository.deduplicate();
  }

  Future<void> _initializeOriginal({bool restore = false}) async {
    final done = await repository.db.rows(
      "SELECT value FROM app_meta WHERE key='builtin_sources'",
    );
    if (done.isNotEmpty && done.first['value'] == '3' && !restore) return;
    final text = await rootBundle.loadString('assets/source_candidates.json');
    final data = jsonDecode(text) as Map;
    final urls = (data['urls'] as List).cast<String>().map(Uri.parse).toSet();
    final precheck =
        jsonDecode(await rootBundle.loadString('assets/source_audit.json'))
            as Map;
    final defaults = <String, bool>{
      for (final result in precheck['results'] as List)
        result['url'] as String: !{
          'unavailable',
          'missingDomain',
          'inconclusive',
        }.contains(result['state']),
    };
    final candidates = [
      for (final uri in urls)
        SourceCandidate(
          name: uri.host,
          endpoint: uri,
          kind: SourceKind.cms,
          requestedEnabled: true,
        ),
      SourceCandidate(
        name: '看剧AI',
        endpoint: Uri.parse('https://kanju3.com/'),
        kind: SourceKind.kanju,
        requestedEnabled: true,
      ),
      SourceCandidate(
        name: '555电影',
        endpoint: Uri.parse('https://wu5mv.com/'),
        kind: SourceKind.macCmsHtml,
        requestedEnabled: true,
      ),
    ];
    await repository.applySubscription(
      origin,
      '内置点播渠道',
      text,
      candidates,
      enableNew: true,
      initialEnabled: defaults,
      deduplicateSources: false,
    );
    await repository.pauseSubscription(stableId(origin.toString()), true);
    if (restore) {
      final identities = SourceIdentityStore(repository.db);
      final ids = {
        for (final item in candidates)
          item: await identities.resolve(item.kind.name, item.endpoint),
      };
      for (final enabled in [true, false]) {
        await repository.batch(
          [
            for (final item in candidates)
              if ((defaults[item.endpoint.toString()] ?? true) == enabled)
                ids[item]!,
          ],
          enabled: enabled,
          suppressed: false,
          deduplicateSources: false,
        );
      }
    }
    await repository.db.write(
      "INSERT OR REPLACE INTO app_meta VALUES('builtin_sources','3')",
    );
  }
}
