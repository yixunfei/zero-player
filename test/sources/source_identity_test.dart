import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/sources/data/catalog_parser.dart';
import 'package:zero_player/features/sources/domain/source_identity.dart';

void main() {
  group('identity rules', _identityTests);
  group('persisted identity', _repositoryTests);
}

void _identityTests() {
  test(
    'identity merges representation and slash variants without merging feeds',
    () {
      String key(String url, [String kind = 'cms']) =>
          sourceIdentity(kind, Uri.parse(url));
      expect(
        key('https://cms.test/api.php/provide/vod/at/xml/?b=2&a=1'),
        key('https://cms.test/api.php/provide/vod?a=1&b=2'),
      );
      expect(
        key('https://cms.test/api?at=xml'),
        key('https://cms.test/api?at=json'),
      );
      expect(
        key('https://cms.test/api?token=a'),
        isNot(key('https://cms.test/api?token=b')),
      );
      expect(
        key('https://cms.test/api?at=custom'),
        isNot(key('https://cms.test/api')),
      );
      expect(key('https://cms.test/api'), isNot(key('http://cms.test/api')));
      expect(
        key('https://cms.test/api/from/a'),
        isNot(key('https://cms.test/api/from/b')),
      );
      expect(
        key('https://cms.test/api', 'cms'),
        isNot(key('https://cms.test/api', 'kanju')),
      );
    },
  );
  test(
    'Maccms category and active fields are parsed, duplicate formats merge',
    () {
      final catalog = const JsonSourceCatalogParser().parse('''[
      {"name":"A","api":"https://cms.test/api/at/xml/","group":"18禁","isActive":true},
      {"name":"B","api":"https://cms.test/api/","group":"18禁"}
    ]''', Uri.parse('https://catalog.test/R18.json'));
      expect(catalog.sources, hasLength(1));
      expect(catalog.sources.single.classification, 'adult');
      expect(catalog.sources.single.requestedEnabled, isTrue);
    },
  );
}

void _repositoryTests() {
  test(
    'shared imports retain manual headers, disable choice and memberships',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final repository = SourceRepository(db);
      final id = await repository.saveManual(
        '我的渠道',
        Uri.parse('https://cms.test/api/'),
        enabled: false,
        headers: {'Referer': 'https://cms.test/'},
      );
      const parser = JsonSourceCatalogParser();
      final candidates = parser
          .parse(
            '[{"name":"订阅名称","api":"https://cms.test/api/at/xml","group":"影视"}]',
            Uri.parse('https://catalog.test/one'),
          )
          .sources;
      final first = Uri.parse('https://catalog.test/one');
      final second = Uri.parse('https://catalog.test/two');
      await repository.applySubscription(first, 'one', 'snapshot', [
        ...candidates,
        ...candidates,
      ], enableNew: true);
      await repository.applySubscription(
        second,
        'two',
        'snapshot',
        candidates,
        enableNew: true,
      );
      await repository.applySubscription(
        second,
        'two',
        'snapshot',
        candidates,
        replaceSources: false,
      );
      final sources = await repository.all();
      expect(sources, hasLength(1));
      expect(sources.single.id, id);
      expect(sources.single.name, '我的渠道');
      expect(sources.single.enabled, isFalse);
      expect(sources.single.headers, {'Referer': 'https://cms.test/'});
      expect(sources.single.classification, 'general');
      expect(await db.rows('SELECT * FROM source_memberships'), hasLength(2));
      await repository.suppress(id, true);
      await repository.applySubscription(second, 'two', 'snapshot', candidates);
      expect(await repository.all(), isEmpty);
      expect(
        (await repository.all(includeSuppressed: true)).single.suppressed,
        isTrue,
      );
    },
  );
  test(
    'manual representation variants resolve the same persisted source',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final repository = SourceRepository(db);
      final first = await repository.saveManual(
        'A',
        Uri.parse('https://cms.test/api/'),
      );
      final second = await repository.saveManual(
        'B',
        Uri.parse('https://cms.test/api/at/xml/'),
      );
      expect(second, first);
      expect(await repository.all(), hasLength(1));
      expect((await repository.all()).single.name, 'B');
    },
  );
}
