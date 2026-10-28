import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/cache/resource_identity.dart';
import 'package:zero_player/media/cache/segment_store.dart';

void main() {
  test(
    'concurrent checksum failures join a single repair without overwriting a lease',
    _concurrentRepair,
  );
  test(
    'failed deletion remains accounted for and unavailable until retry succeeds',
    _failedDeletion,
  );
}

Future<void> _concurrentRepair() async {
  final fixture = await _Fixture.create([9, 9, 9]);
  final repaired = Completer<void>();
  fixture.file.repaired = repaired;
  var loads = 0;
  Future<StoredResource> repair() async {
    loads++;
    final result = await fixture.store.write(
      fixture.key,
      Stream.value([1, 2, 3]),
      statusCode: 200,
      headers: {},
    );
    if (!repaired.isCompleted) repaired.complete();
    return result;
  }

  final leases = await Future.wait(
    List.generate(
      3,
      (_) => fixture.store.acquire(fixture.key, repair, verify: true),
    ),
  );
  expect(loads, 1);
  expect(
    fixture.file.reads,
    1,
    reason: 'verification itself is shared, not only the fetch',
  );
  for (final lease in leases) {
    expect(await lease.resource.file.readAsBytes(), [1, 2, 3]);
    lease.release();
  }
}

Future<void> _failedDeletion() async {
  final fixture = await _Fixture.create([1, 2, 3]);
  fixture.file.denyDelete = true;
  await expectLater(
    fixture.store.clearUnused(),
    throwsA(isA<FileSystemException>()),
  );
  expect(fixture.store.sizeBytes, 3);
  expect(fixture.store.find(fixture.key), isNotNull);
  await expectLater(
    fixture.store.acquire(
      fixture.key,
      () async => throw StateError('unexpected fetch'),
    ),
    throwsA(isA<FileSystemException>()),
  );
  fixture.file.denyDelete = false;
  await fixture.store.clearUnused();
  expect(fixture.store.sizeBytes, 0);
  expect(await fixture.file.exists(), isFalse);
}

final class _Fixture {
  _Fixture(this.store, this.file, this.key);
  final SegmentStore store;
  final _ControlledFile file;
  final String key;
  static Future<_Fixture> create(List<int> contents) async {
    final directory = await Directory.systemTemp.createTemp('cache-race');
    addTearDown(() => directory.delete(recursive: true));
    final key = resourceIdentity(Uri.parse('https://test/segment'), {}, null);
    final file = _ControlledFile(File('${directory.path}/$key.bin'));
    await file.inner.writeAsBytes(contents);
    final store = SegmentStore(directory);
    final lease = await store.acquire(
      key,
      () async => StoredResource(
        file: file,
        length: 3,
        digest: sha256.convert([1, 2, 3]).toString(),
        statusCode: 200,
        headers: {},
      ),
    );
    lease.release();
    return _Fixture(store, file, key);
  }
}

final class _ControlledFile implements File {
  _ControlledFile(this.inner);
  final File inner;
  bool denyDelete = false;
  int reads = 0;
  Completer<void>? repaired;
  @override
  Future<bool> exists() => inner.exists();
  @override
  Future<int> length() => inner.length();
  @override
  Future<File> delete({bool recursive = false}) async {
    if (denyDelete) throw const FileSystemException('simulated locked file');
    await inner.delete(recursive: recursive);
    return inner;
  }

  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    final call = ++reads;
    final snapshot = await inner.readAsBytes();
    if (call > 1 && repaired != null) {
      await repaired!.future;
      await Future<void>.delayed(Duration.zero);
    }
    yield snapshot;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
