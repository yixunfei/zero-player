import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/cache/resource_identity.dart';
import 'package:zero_player/media/cache/segment_store.dart';

void main() {
  late Directory directory;
  late SegmentStore store;
  String key(String suffix) =>
      resourceIdentity(Uri.parse('https://test/$suffix'), {}, null);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zero-cache-test-');
    store = SegmentStore(directory, maxBytes: 10, maxResourceBytes: 10);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<StoredResource> write(String name, int size, {int? expected}) =>
      store.write(
        key(name),
        Stream.value(List.filled(size, 42)),
        statusCode: 200,
        headers: {},
        expectedLength: expected,
      );

  identityTests();

  test(
    'concurrent consumers share one download and independently release',
    () async {
      var loads = 0;
      final gate = Completer<void>();
      Future<StoredResource> load() async {
        loads++;
        await gate.future;
        return write('a', 5);
      }

      final first = store.acquire(key('a'), load);
      final second = store.acquire(key('a'), load);
      gate.complete();
      final leases = await Future.wait([first, second]);
      expect(loads, 1);
      expect(leases[0].resource.digest, leases[1].resource.digest);
      leases[0].release();
      expect(await leases[1].resource.file.readAsBytes(), List.filled(5, 42));
      leases[1].release();
    },
  );

  test('leased resources cannot be evicted; released resources can', () async {
    final lease = await store.acquire(key('a'), () => write('a', 8));
    await expectLater(
      store.acquire(key('b'), () => write('b', 5)),
      throwsA(isA<FileSystemException>()),
    );
    expect(await lease.resource.file.exists(), isTrue);
    lease.release();
    final next = await store.acquire(key('b'), () => write('b', 5));
    expect(await lease.resource.file.exists(), isFalse);
    expect(store.sizeBytes, 5);
    next.release();
  });

  test('truncated and oversized writes never become committed files', () async {
    await expectLater(
      write('a', 5, expected: 6),
      throwsA(isA<HttpException>()),
    );
    await expectLater(write('b', 11), throwsA(isA<FileSystemException>()));
    expect(await directory.list().toList(), isEmpty);
    expect(store.sizeBytes, 0);
  });

  test('simultaneous commits obey total capacity', () async {
    final results = await Future.wait([
      store
          .acquire(key('a'), () => write('a', 8))
          .then<Object>((v) => v, onError: (Object e) => e),
      store
          .acquire(key('b'), () => write('b', 8))
          .then<Object>((v) => v, onError: (Object e) => e),
    ]);
    expect(results.whereType<ResourceLease>().length, 1);
    expect(results.whereType<FileSystemException>().length, 1);
    expect(store.sizeBytes, lessThanOrEqualTo(10));
    for (final lease in results.whereType<ResourceLease>()) {
      lease.release();
    }
  });
}

void identityTests() {
  test('cache identity includes signed query headers and byte ranges', () {
    final uri = Uri.parse('https://test/video?token=one');
    expect(
      resourceIdentity(uri, {'Authorization': 'a'}, null),
      resourceIdentity(uri, {'authorization': 'a'}, null),
    );
    expect(
      resourceIdentity(uri, {'authorization': 'b'}, null),
      isNot(resourceIdentity(uri, {'authorization': 'a'}, null)),
    );
    expect(
      resourceIdentity(uri, {}, 'bytes=0-9'),
      isNot(resourceIdentity(uri, {}, null)),
    );
    expect(
      resourceIdentity(uri.replace(query: 'token=two'), {}, null),
      isNot(resourceIdentity(uri, {}, null)),
    );
  });
}
