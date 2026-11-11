import 'dart:convert';
import 'package:flutter/services.dart';
import '../data/source_repository.dart';
import '../data/source_identity_store.dart';
import '../domain/source_catalog.dart';
import '../domain/video_source.dart';
import 'maccms_sources.dart';
import '../data/source_preferences.dart';
import 'source_curation.dart';
import '../data/awesome_zhuiju_index.dart';
import '../data/catalog_parser.dart';

final class BuiltinSources {
  const BuiltinSources(this.repository);
  final SourceRepository repository;
  static final origin = Uri.parse(
    'https://github.com/LibreSpark/LibreTV/discussions/652#builtin',
  );

  Future<void> initialize({bool restore = false}) async {
    await _initializeOriginal(restore: restore);
    await MaccmsSources(repository).initialize(restore: restore);
    await _initializeAwesome(restore: restore);
    await SourceCuration(repository).initialize(restore: restore);
    await repository.applyVerifiedContentLabels();
    await SourcePreferences(
      repository.db,
    ).seedDefaults(await repository.all(includeSuppressed: true));
    await repository.deduplicate();
  }

  Future<void> _initializeAwesome({required bool restore}) async {
    final url = Uri.parse(awesomeZhuijuBuiltin);
    final id = stableId('$url');
    final text = await rootBundle.loadString(
      'assets/awesome_zhuiju_verified.json',
    );
    final current = await repository.db.rows(
      'SELECT snapshot FROM subscriptions WHERE id=?',
      [id],
    );
    if (!restore && current.firstOrNull?['snapshot'] == text) return;
    final members = {
      for (final row in await repository.db.rows(
        'SELECT source_id FROM source_memberships WHERE subscription_id=?',
        [id],
      ))
        row['source_id'] as String,
    };
    final existing = {
      for (final source in await repository.all(includeSuppressed: true))
        if (!members.contains(source.id))
          AwesomeZhuijuIndex.videoIdentity(source.kind, source.endpoint),
    };
    final candidates = const JsonSourceCatalogParser()
        .parse(text, url)
        .sources
        .where(
          (item) => existing.add(
            AwesomeZhuijuIndex.videoIdentity(item.kind.name, item.endpoint),
          ),
        )
        .toList();
    await repository.applySubscription(
      url,
      'awesome-zhuiju-free · 内置精选',
      text,
      candidates,
      enableNew: true,
      deduplicateSources: false,
    );
    await repository.pauseSubscription(id, true);
    if (restore) {
      final restored = await repository.db.rows(
        'SELECT source_id FROM source_memberships WHERE subscription_id=?',
        [id],
      );
      await repository.batch(
        restored.map((row) => row['source_id'] as String).toList(),
        enabled: true,
        suppressed: false,
        deduplicateSources: false,
      );
    }
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
        Uri.parse(result['url'] as String).toString(): !{
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
