import 'package:flutter/services.dart';
import '../data/catalog_parser.dart';
import '../data/source_identity_store.dart';
import '../data/source_repository.dart';
import '../domain/video_source.dart';
import '../domain/source_catalog.dart';

final class MaccmsSources {
  const MaccmsSources(this.repository);
  final SourceRepository repository;

  Future<void> initialize({bool restore = false}) async {
    final done = await repository.db.rows(
      "SELECT value FROM app_meta WHERE key='builtin_maccms'",
    );
    if (done.isNotEmpty && done.single['value'] == '2' && !restore) return;
    await SourceIdentityStore(repository.db).consolidate();
    for (final file in ['Site.json', 'R18.json']) {
      await _import(file, restore);
    }
    await repository.db.write(
      "INSERT OR REPLACE INTO app_meta VALUES('builtin_maccms','2')",
    );
  }

  Future<void> _import(String file, bool restore) async {
    final adult = file == 'R18.json';
    final origin = Uri.parse(
      'https://raw.githubusercontent.com/ZhaoYunxiong/MaccmsResources/main/$file',
    );
    final text = await rootBundle.loadString('assets/catalogs/maccms/$file');
    final catalog = const JsonSourceCatalogParser().parse(text, origin);
    await repository.applySubscription(
      origin,
      adult ? 'MaccmsResources · 成人' : 'MaccmsResources · 普通',
      text,
      adult
          ? [
              for (final c in catalog.sources)
                SourceCandidate(
                  name: c.name,
                  endpoint: c.endpoint,
                  kind: c.kind,
                  requestedEnabled: false,
                  classification: 'adult',
                ),
            ]
          : catalog.sources,
      enableNew: !adult,
      deduplicateSources: false,
    );
    await repository.pauseSubscription(stableId(origin.toString()), true);
    if (!restore) return;
    final ids = await repository.db.rows(
      'SELECT source_id FROM source_memberships WHERE subscription_id=?',
      [stableId(origin.toString())],
    );
    await repository.batch(
      ids.map((row) => row['source_id'] as String).toList(),
      enabled: !adult,
      suppressed: false,
      deduplicateSources: false,
    );
  }
}
