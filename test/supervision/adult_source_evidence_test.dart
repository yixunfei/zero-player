import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import 'package:zero_player/features/supervision/domain/adult_source_evidence.dart';
import '../../test_support/supervision_fixture.dart';

void main() {
  test(
    'verified adult publishers do not depend on ambiguous names or paths',
    () {
      for (final host in [
        'slapibf.com',
        'shayuapi.com',
        'www.shayuapi.com',
        'SHAYUAPI.COM.',
      ]) {
        expect(knownAdultHost(host), isTrue);
      }
      for (final host in [
        'forest.test',
        'shark.test',
        'shayuapi.com.example.org',
        'notshayuapi.com',
      ]) {
        expect(knownAdultHost(host), isFalse);
      }
    },
  );

  test(
    'source evidence requires several adult labels and no mainstream catalog',
    () {
      expect(adultCatalog(['国产色情', '亚洲无码', '强奸乱伦', '精品推荐']), isTrue);
      expect(adultCatalog(['伦理', '电影']), isFalse);
      expect(adultCatalog(['伦理', '伦理', '伦理']), isFalse);
      expect(adultCatalog(['国产色情', '亚洲无码', '强奸乱伦', '纪录片']), isFalse);
      expect(adultCatalog([]), isFalse);
    },
  );

  test(
    'unknown forest and shark sources are hidden; ordinary names remain usable',
    () async {
      final f = SupervisionFixture();
      addTearDown(f.close);
      await f.load();
      for (final entry in {'森林': 'slapibf.com', '鲨鱼': 'shayuapi.com'}.entries) {
        final id = await f.sources.saveManual(
          entry.key,
          Uri.https(entry.value, '/alias'),
        );
        expect(f.policy.sourceAllowed((await f.sources.find(id))!), isFalse);
      }
      await f.sources.applyVerifiedContentLabels();
      expect(
        (await f.sources.all()).every((s) => s.classification == 'adult'),
        isTrue,
      );
      expect(
        f.policy.sourceAllowed(
          VideoSource(
            id: 'nature',
            name: '森林与鲨鱼纪录片',
            endpoint: Uri.parse('https://nature.test/api'),
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'new adult taxonomy updates the policy immediately and persists classification',
    () async {
      final f = SupervisionFixture();
      addTearDown(f.close);
      await f.load();
      final id = await f.sources.saveManual(
        '中性名称',
        Uri.parse('https://fixture.test/api'),
      );
      final source = (await f.sources.find(id))!;
      var changes = 0;
      f.policy.addListener(() => changes++);
      expect(f.policy.sourceAllowed(source), isTrue);
      await f.sources.classifyCatalog(id, {
        '1': '国产色情',
        '2': '亚洲无码',
        '3': '强奸乱伦',
      });
      expect(f.policy.sourceAllowed(source), isFalse);
      expect((await f.sources.find(id))!.classification, 'adult');
      expect(changes, greaterThan(0));
    },
  );
}
