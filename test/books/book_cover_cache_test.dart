import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/book_cover_cache.dart';
import 'package:zero_player/features/books/data/qidian_catalog.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';
import 'package:zero_player/features/settings/domain/settings_validation.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
);

void main() {
  _policyAndSettingsTests();
  test(
    'cover cache persists, separates identities and obeys cleanup',
    () async {
      final root = await Directory.systemTemp.createTemp('book-cover-cache-');
      addTearDown(() => root.delete(recursive: true));
      final cache = BookCoverCache(Directory('${root.path}/covers'));
      final uri = Uri.parse('https://bookcover.yuewen.com/cover/1.png');
      final key = cache.key('同名作品', '作者甲', uri);
      final other = cache.key('同名作品', '作者乙', uri);
      final changed = cache.key(
        '同名作品',
        '作者甲',
        Uri.parse('https://bookcover.yuewen.com/cover/2.png'),
      );
      expect(other, isNot(key));
      expect(changed, isNot(key));
      await cache.write(key, _png, cache.generation);
      final reopened = BookCoverCache(Directory('${root.path}/covers'));
      expect(await reopened.read(key), _png);
      expect(
        identical(await reopened.read(key), await reopened.read(key)),
        isTrue,
      );
      expect(await reopened.read(other), isNull);
      expect((await reopened.usage()).entries, 1);
      var changes = 0;
      reopened.addListener(() => changes++);
      await reopened.clear();
      expect(changes, greaterThan(0));
      expect((await reopened.usage()).entries, 0);
      await reopened.write(key, _png, reopened.generation);
      final oldGeneration = reopened.generation;
      await reopened.setMaxMiB(0);
      await reopened.write(key, _png, oldGeneration);
      expect(await reopened.read(key), isNull);
      expect((await reopened.usage()).bytes, 0);
    },
  );

  test('cover cache evicts the oldest files at its disk limit', () async {
    final root = await Directory.systemTemp.createTemp('book-cover-limit-');
    addTearDown(() => root.delete(recursive: true));
    final cache = BookCoverCache(Directory('${root.path}/covers'), maxMiB: 1);
    final largeImage = List<int>.filled(700 * 1024, 0)
      ..[0] = 0xff
      ..[1] = 0xd8
      ..[2] = 0xff;
    final first = cache.key('甲', '作者', Uri.parse('https://fixture.test/1'));
    final second = cache.key('乙', '作者', Uri.parse('https://fixture.test/2'));
    await cache.write(first, largeImage, cache.generation);
    await cache.write(second, largeImage, cache.generation);
    expect(await cache.read(first), isNull);
    expect(await cache.read(second), isNotNull);
    expect((await cache.usage()).bytes, lessThanOrEqualTo(1024 * 1024));
  });
}

void _policyAndSettingsTests() {
  test('cached Qidian cover still obeys supervision policy', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final root = await Directory.systemTemp.createTemp('book-cover-policy-');
    final services = AppServices.scoped(root, AppDatabase.memory());
    addTearDown(() async {
      await services.close();
      await root.delete(recursive: true);
    });
    await services.settings.load();
    await services.supervision.load();
    final book = Book(
      qidianRecommendationId,
      BookKind.text,
      '缓存作品',
      '作者',
      qidianHome.resolve('/book/1040765595/'),
      cover: 'https://bookcover.yuewen.com/cover/1.png',
    );
    final cache = services.books.coverCache;
    final key = cache.key(book.title, book.author, Uri.parse(book.cover));
    await cache.write(key, _png, cache.generation);
    expect(await services.books.coverBytes(book, CancellationToken()), _png);
    final credentials = await services.supervision.prepareCredentials(
      'cover-policy-test-password',
    );
    await services.supervision.saveCredentials(credentials);
    await expectLater(
      services.books.coverBytes(book, CancellationToken()),
      throwsA(isA<ContentBlocked>()),
    );
    expect((await cache.usage()).entries, 0);
  });

  test('cover cache capacity setting accepts disable and bounded sizes', () {
    validateSetting('bookCoverCacheMiB', 0);
    validateSetting('bookCoverCacheMiB', 128);
    expect(
      () => validateSetting('bookCoverCacheMiB', 129),
      throwsFormatException,
    );
    expect(UserSettings.fromMap(const {}).bookCoverCacheMiB, 32);
    expect(
      UserSettings.fromMap(const {'bookCoverCacheMiB': 64}).bookCoverCacheMiB,
      64,
    );
  });
}
