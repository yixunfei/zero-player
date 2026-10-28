import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/catalog/domain/vod_provider.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import 'package:zero_player/features/supervision/data/filtering_vod_provider.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/supervision_fixture.dart';

final class FixtureProvider implements VodProvider {
  final items = <CatalogItem>[];
  Map<String, String> categories = {'1': '电影', '9': '日韩伦理'};
  Completer<void>? detailBarrier;
  int browses = 0;
  @override
  Future<CatalogBrowse> browse({String category = '', int page = 1}) async {
    browses++;
    return CatalogBrowse(CatalogPage(items, 1), categories: categories);
  }

  @override
  Future<CatalogPage> search(String query, {int page = 1}) async =>
      CatalogPage(items, 1);
  @override
  Future<CatalogItem> detail(String remoteId) async {
    if (detailBarrier != null) await detailBarrier!.future;
    return items.singleWhere((i) => i.id == remoteId);
  }

  @override
  Future<ResolvedMedia> resolve(Episode episode) async =>
      ResolvedMedia(episode.uri);
}

late SupervisionFixture f;
late FixtureProvider inner;
late FilteringVodProvider provider;

void main() {
  setUp(() async {
    f = SupervisionFixture();
    await f.load();
    inner = FixtureProvider();
    provider = FilteringVodProvider(
      inner,
      VideoSource(
        id: 's',
        name: 'ordinary',
        endpoint: Uri.parse('https://example.org/api'),
      ),
      f.policy,
    );
  });
  tearDown(() => f.close());
  _registerCases0();
  _registerCases1();
  _staleSourceTest();
}

void _staleSourceTest() {
  test(
    'an old provider cannot overwrite a newer adult source classification',
    () async {
      inner.items.add(
        const CatalogItem(sourceId: 's', id: 'movie', title: 'ordinary'),
      );
      await provider.search('ordinary');
      f.policy.rememberSource(
        VideoSource(
          id: 's',
          name: 'ordinary',
          endpoint: Uri.parse('https://example.org/api'),
          classification: 'adult',
        ),
      );
      await expectLater(
        provider.detail('movie'),
        throwsA(isA<ContentBlocked>()),
      );
      expect(f.policy.sourceIdAllowed('s'), isFalse);
    },
  );
}

void _registerCases0() {
  test(
    'missing category names are resolved once and adult categories excluded',
    () async {
      inner.items.addAll([
        const CatalogItem(
          sourceId: 's',
          id: 'normal',
          title: '普通电影',
          categoryId: '1',
        ),
        const CatalogItem(
          sourceId: 's',
          id: 'adult',
          title: '普通片名',
          categoryId: '9',
        ),
        const CatalogItem(
          sourceId: 's',
          id: 'tagged',
          title: '普通片名',
          tags: '伦理',
        ),
      ]);
      expect((await provider.search('片名')).items.map((i) => i.id), ['normal']);
      expect((await provider.search('片名')).items.single.category, '电影');
      expect(inner.browses, 1);
      expect((await provider.browse()).categories, {'1': '电影'});
      await expectLater(
        provider.detail('adult'),
        throwsA(isA<ContentBlocked>()),
      );
    },
  );
  test(
    'unverified category IDs fail closed while content is filtered',
    () async {
      inner.items.add(
        const CatalogItem(
          sourceId: 's',
          id: 'unknown',
          title: '未知',
          categoryId: 'missing',
        ),
      );
      expect((await provider.search('未知')).items, isEmpty);
      await expectLater(
        provider.detail('unknown'),
        throwsA(isA<ContentBlocked>()),
      );
    },
  );
}

void _registerCases1() {
  test(
    'rules changed during a request are checked again on completion',
    () async {
      await f.configure();
      inner.items.add(
        const CatalogItem(sourceId: 's', id: 'movie', title: 'restricted'),
      );
      inner.detailBarrier = Completer<void>();
      final pending = provider.detail('movie');
      final denied = expectLater(pending, throwsA(isA<ContentBlocked>()));
      await f.authorized(
        SensitiveOperation.supervision,
        () => f.guard.updateRules(SupervisionRules(keywords: ['restricted'])),
      );
      inner.detailBarrier!.complete();
      await denied;
    },
  );
  test(
    'adult source aliases and direct resolution obey source rules',
    () async {
      final adult = VideoSource(
        id: 'unknown',
        name: '未标记 ＡＶ 渠道',
        endpoint: Uri.parse('https://example.org/api'),
      );
      final filtered = FilteringVodProvider(inner, adult, f.policy);
      await expectLater(
        filtered.resolve(
          Episode('1', Uri.parse('https://example.org/movie.mp4')),
        ),
        throwsA(isA<ContentBlocked>()),
      );
      expect(f.policy.sourceAllowed(adult), isFalse);
    },
  );
}
