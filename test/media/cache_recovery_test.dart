import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/persistence/segment_index.dart';
import 'package:zero_player/media/cache/resource_identity.dart';
import 'package:zero_player/media/cache/segment_fetcher.dart';
import 'package:zero_player/media/cache/segment_metadata.dart';
import 'package:zero_player/media/cache/segment_prefetcher.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import '../../test_support/http_test_server.dart';

void main() {
  _corruptionTests();
  _pinTests();
  _budgetTests();
}

void _corruptionTests() {
  test(
    'verified cache hit evicts same-size corrupt content and refetches',
    () async {
      final fixture = await _Fixture.create();
      final server = await HttpTestServer.start(
        (request) => request.response.add([1, 2, 3, 4]),
      );
      addTearDown(server.close);
      final uri = server.baseUri.resolve('segment.ts');
      final policy = HeaderPolicy({});
      final fetcher = SegmentFetcher(fixture.store, fixture.http);
      var lease = await fetcher.fetch(uri, policy);
      final file = lease.resource.file;
      lease.release();
      await file.writeAsBytes([9, 9, 9, 9]);
      lease = await fetcher.fetch(uri, policy, verify: true);
      expect(await lease.resource.file.readAsBytes(), [1, 2, 3, 4]);
      lease.release();
      expect(server.calls['/segment.ts'], 2);
      await file.writeAsBytes([8, 8, 8, 8]);
      final key = resourceIdentity(uri, {}, null);
      await expectLater(
        fixture.store.verify(key),
        throwsA(isA<FileSystemException>()),
      );
      expect(fixture.store.find(key), isNull);
      expect(await fixture.metadata.entries(), isEmpty);
    },
  );
}

void _pinTests() {
  test(
    'unpin preserves other owners while the metadata snapshot is pending',
    () async {
      final fixture = await _Fixture.create();
      await fixture.write('a', 8);
      await fixture.store.pin('owner-a', _key('a'));
      await fixture.write('b', 8);
      await fixture.store.pin('owner-b', _key('b'));
      final hold = Completer<void>();
      final queried = Completer<void>();
      fixture.metadata.hold = hold;
      fixture.metadata.queried = queried;
      final unpin = fixture.store.unpin('owner-a');
      await queried.future;
      try {
        expect(
          fixture.store.cacheBytes,
          0,
          reason: 'old protection stays until snapshot is ready',
        );
      } finally {
        hold.complete();
      }
      await unpin;
      await fixture.write('c', 8);
      expect(fixture.store.find(_key('a')), isNull);
      expect(fixture.store.find(_key('b')), isNotNull);
      expect(await fixture.metadata.protectedKeys(), {_key('b')});
    },
  );
  test(
    'in-memory pins preserve another owner when one owner is removed',
    () async {
      final fixture = await _Fixture.create();
      final store = SegmentStore(fixture.directory, maxBytes: 10);
      await store.write(
        _key('a'),
        Stream.value([1, 2, 3]),
        statusCode: 200,
        headers: {},
      );
      await store.pin('first', _key('a'));
      await store.pin('second', _key('a'));
      await store.unpin('first');
      await store.clearUnused();
      expect(store.find(_key('a')), isNotNull);
      await store.unpin('second');
      await store.clearUnused();
      expect(store.find(_key('a')), isNull);
    },
  );
}

void _budgetTests() {
  test(
    'episode cache budget releases old resident content and resumes caching',
    () async {
      final fixture = await _Fixture.create();
      final prefetch = SegmentPrefetcher(
        SegmentFetcher(fixture.store, fixture.http),
        HeaderPolicy({}),
      )..maxBytes = 5;
      await fixture.write('a', 4);
      prefetch.observe(Uri.parse('https://test/a'), 4);
      await fixture.write('b', 4);
      prefetch.observe(Uri.parse('https://test/b'), 4);
      expect(prefetch.hasRoom, isFalse);
      expect(await prefetch.prepare(), isTrue);
      expect(fixture.store.find(_key('a')), isNull);
      expect(fixture.store.find(_key('b')), isNotNull);
      await fixture.store.clearUnused();
      expect(prefetch.hasRoom, isTrue);
    },
  );
}

String _key(String name) =>
    resourceIdentity(Uri.parse('https://test/$name'), {}, null);

final class _Fixture {
  _Fixture(this.directory, this.db) {
    metadata = _DelayedMetadata(SegmentIndex(db));
    store = SegmentStore(directory, maxBytes: 10, metadata: metadata);
  }
  final Directory directory;
  final AppDatabase db;
  final http = MediaHttpClient(allowPrivateNetworks: true);
  late final _DelayedMetadata metadata;
  late final SegmentStore store;
  static Future<_Fixture> create() async {
    final fixture = _Fixture(
      await Directory.systemTemp.createTemp('cache-recovery'),
      AppDatabase.memory(),
    );
    await fixture.store.initialize();
    addTearDown(() async {
      fixture.http.close();
      await fixture.db.close();
      await fixture.directory.delete(recursive: true);
    });
    return fixture;
  }

  Future<StoredResource> write(String name, int bytes) => store.write(
    _key(name),
    Stream.value(List.filled(bytes, 42)),
    statusCode: 200,
    headers: {},
  );
}

final class _DelayedMetadata implements SegmentMetadata {
  _DelayedMetadata(this.inner);
  final SegmentMetadata inner;
  Completer<void>? hold;
  Completer<void>? queried;
  @override
  Future<Set<String>> protectedKeys() async {
    if (queried?.isCompleted == false) queried!.complete();
    await hold?.future;
    return inner.protectedKeys();
  }

  @override
  Future<Map<String, StoredResource>> entries() => inner.entries();
  @override
  Future<Set<String>> ownedKeys(String owner) => inner.ownedKeys(owner);
  @override
  Future<void> put(String key, StoredResource value) => inner.put(key, value);
  @override
  Future<void> remove(String key) => inner.remove(key);
  @override
  Future<void> pin(String owner, String key) => inner.pin(owner, key);
  @override
  Future<void> unpin(String owner) => inner.unpin(owner);
  @override
  Future<void> retainPins(String owner, Set<String> keys) =>
      inner.retainPins(owner, keys);
}
