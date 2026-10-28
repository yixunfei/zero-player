import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'segment_metadata.dart';

final class StoredResource {
  const StoredResource({
    required this.file,
    required this.length,
    required this.digest,
    required this.statusCode,
    required this.headers,
  });
  final File file;
  final int length;
  final String digest;
  final int statusCode;
  final Map<String, String> headers;
}

final class ResourceLease {
  ResourceLease(this.resource, this._release);
  final StoredResource resource;
  final void Function() _release;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

/// Atomic shared segments with transient leases and durable download pins.
final class SegmentStore {
  SegmentStore(
    this.directory, {
    this.maxBytes = 256 * 1024 * 1024,
    this.maxResourceBytes = 64 * 1024 * 1024,
    this.metadata,
  });
  final Directory directory;
  int maxBytes;
  final int maxResourceBytes;
  final SegmentMetadata? metadata;
  final _protected = <String>{};
  final _localPins = <String, Set<String>>{};
  final _entries = <String, StoredResource>{};
  final _pending = <String, ({Future<StoredResource> future, bool verifies})>{};
  final _invalid = <String>{};
  final _references = <String, int>{};
  Future<void> _commits = Future.value();
  int hits = 0;
  int writes = 0;
  int get sizeBytes => _entries.values.fold(0, (sum, e) => sum + e.length);
  int get cacheBytes => _entries.entries
      .where((e) => !_protected.contains(e.key))
      .fold(0, (sum, e) => sum + e.value.length);
  StoredResource? find(String key) => _entries[key];

  Future<Map<String, int>> pinnedResources(String owner) => _serialize(
    () async {
      final keys = await metadata?.ownedKeys(owner) ?? _localPins[owner] ?? {};
      return {
        for (final key in keys)
          if (_entries.containsKey(key)) key: _entries[key]!.length,
      };
    },
  );

  Future<void> initialize() async {
    await directory.create(recursive: true);
    final entries = await metadata?.entries() ?? {};
    for (final entry in entries.entries) {
      if (p.isWithin(directory.absolute.path, entry.value.file.absolute.path) &&
          await entry.value.file.exists() &&
          await entry.value.file.length() == entry.value.length) {
        _entries[entry.key] = entry.value;
      } else {
        await metadata?.remove(entry.key);
      }
    }
    _protected.addAll(await metadata?.protectedKeys() ?? {});
    await for (final file in directory.list()) {
      if (file is File &&
          RegExp(r'^[a-f0-9]{64}\.part$').hasMatch(p.basename(file.path))) {
        await file.delete();
      }
    }
  }

  Future<void> pin(String owner, String key) => _serialize(() async {
    if (!_entries.containsKey(key)) throw StateError('Segment not committed');
    await metadata?.pin(owner, key);
    if (metadata == null) _localPins.putIfAbsent(owner, () => {}).add(key);
    _protected.add(key);
  });

  Future<void> unpin(String owner) => _serialize(() async {
    await metadata?.unpin(owner);
    _localPins.remove(owner);
    await _refreshProtected();
  });

  Future<void> _refreshProtected() async {
    final keys =
        await metadata?.protectedKeys() ??
        _localPins.values.expand((keys) => keys).toSet();
    _protected
      ..clear()
      ..addAll(keys);
  }

  Future<void> verify(String key) async {
    final resource = _entries[key];
    if (resource == null || !await _valid(resource, digest: true)) {
      if (resource != null) await _discard(key, resource);
      throw const FileSystemException('离线分片缺失或损坏，请重新下载');
    }
  }

  Future<bool> _valid(StoredResource resource, {bool digest = false}) async {
    try {
      if (await resource.file.length() != resource.length) return false;
      return !digest ||
          '${await sha256.bind(resource.file.openRead()).first}' ==
              resource.digest;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _discard(String key, StoredResource expected) =>
      _serialize(() async {
        if (identical(_entries[key], expected)) await _removeEntry(key);
      });

  Future<void> retainPins(String owner, Set<String> keys) =>
      _serialize(() async {
        await metadata?.retainPins(owner, keys);
        _localPins[owner]?.retainAll(keys);
        await _refreshProtected();
      });

  Future<void> clearUnused() => _serialize(() async {
    for (final key in _entries.keys.toList()) {
      if (_protected.contains(key) || _references.containsKey(key)) continue;
      await _removeEntry(key);
    }
  });

  Future<int> evictUnused(Iterable<String> keys, int bytesToFree) => _serialize(
    () async {
      var freed = 0;
      for (final key in keys) {
        if (freed >= bytesToFree) break;
        if (_protected.contains(key) || _references.containsKey(key)) continue;
        final entry = _entries[key];
        if (entry == null) continue;
        await _removeEntry(key);
        freed += entry.length;
      }
      return freed;
    },
  );

  Future<void> _removeEntry(String key) async {
    final entry = _entries[key];
    if (entry == null) return;
    // A failed filesystem delete remains accounted for and recoverable. New
    // readers must retry deletion instead of acquiring an invalid resource.
    _invalid.add(key);
    if (await entry.file.exists()) await entry.file.delete();
    await metadata?.remove(key);
    _entries.remove(key);
    _invalid.remove(key);
    _protected.remove(key);
    for (final pins in _localPins.values) {
      pins.remove(key);
    }
  }

  Future<ResourceLease> acquire(
    String key,
    Future<StoredResource> Function() load, {
    bool verify = false,
  }) async {
    _references.update(key, (value) => value + 1, ifAbsent: () => 1);
    try {
      final entry = await _acquireEntry(key, load, verify);
      return ResourceLease(entry, () => _release(key));
    } catch (_) {
      _release(key);
      rethrow;
    }
  }

  Future<StoredResource> _acquireEntry(
    String key,
    Future<StoredResource> Function() load,
    bool verify,
  ) async {
    final pending = _pending[key];
    if (pending != null) {
      hits++;
      final entry = await pending.future;
      if (!verify || pending.verifies) return entry;
      if (_pending[key] == pending) _pending.remove(key);
      return _acquireEntry(key, load, true);
    }
    final work = _resolveEntry(key, load, verify);
    final operation = (future: work, verifies: verify);
    _pending[key] = operation;
    try {
      return await work;
    } finally {
      if (_pending[key] == operation) _pending.remove(key);
    }
  }

  Future<StoredResource> _resolveEntry(
    String key,
    Future<StoredResource> Function() load,
    bool verify,
  ) async {
    var entry = _entries[key];
    if (entry != null &&
        (_invalid.contains(key) || !await _valid(entry, digest: verify))) {
      await _discard(key, entry);
      entry = null;
    }
    if (entry == null) return _load(key, load);
    hits++;
    _entries.remove(key);
    _entries[key] = entry;
    return entry;
  }

  Future<StoredResource> _load(
    String key,
    Future<StoredResource> Function() load,
  ) async {
    final result = await load();
    _entries[key] = result;
    writes++;
    return result;
  }

  void _release(String key) {
    final count = (_references[key] ?? 1) - 1;
    if (count == 0) {
      _references.remove(key);
    } else {
      _references[key] = count;
    }
  }

  Future<StoredResource> write(
    String key,
    Stream<List<int>> body, {
    required int statusCode,
    required Map<String, String> headers,
    int? expectedLength,
  }) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw ArgumentError('Cache key must be a SHA-256 digest');
    }
    await directory.create(recursive: true);
    final temporary = File(p.join(directory.path, '$key.part'));
    final target = File(p.join(directory.path, '$key.bin'));
    final sink = temporary.openWrite();
    var bytes = 0;
    try {
      await for (final chunk in body) {
        bytes += chunk.length;
        if (bytes > maxResourceBytes || bytes > maxBytes) {
          throw const FileSystemException('Resource exceeds cache budget');
        }
        sink.add(chunk);
        if (bytes % (1024 * 1024) < chunk.length) await sink.flush();
      }
      await sink.close();
      if (expectedLength != null && bytes != expectedLength) {
        throw const HttpException('Incomplete resource');
      }
      final digest = await sha256.bind(temporary.openRead()).first;
      return await _commit(
        key,
        temporary,
        target,
        bytes,
        '$digest',
        statusCode,
        headers,
      );
    } catch (_) {
      await sink.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<StoredResource> _commit(
    String key,
    File temporary,
    File target,
    int bytes,
    String digest,
    int statusCode,
    Map<String, String> headers,
  ) => _serialize(() async {
    await _makeRoom(bytes);
    await temporary.rename(target.path);
    final result = StoredResource(
      file: target,
      length: bytes,
      digest: digest,
      statusCode: statusCode,
      headers: Map.unmodifiable(headers),
    );
    await metadata?.put(key, result);
    _entries[key] = result;
    return result;
  });

  Future<T> _serialize<T>(Future<T> Function() action) async {
    final previous = _commits;
    final done = Completer<void>();
    _commits = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<void> _makeRoom(int bytes) async {
    // No awaits between reservation check and reference check; entries in use
    // are never removed. Serial gateway downloads are not assumed.
    var current = cacheBytes;
    for (final key in _entries.keys.toList()) {
      if (current + bytes <= maxBytes) return;
      if (_references.containsKey(key) || _protected.contains(key)) continue;
      current -= _entries[key]!.length;
      await _removeEntry(key);
    }
    if (current + bytes > maxBytes) {
      throw const FileSystemException('Cache is full with active resources');
    }
  }
}
