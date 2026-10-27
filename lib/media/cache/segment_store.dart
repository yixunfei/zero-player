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
  final _entries = <String, StoredResource>{};
  final _pending = <String, Future<StoredResource>>{};
  final _references = <String, int>{};
  Future<void> _commits = Future.value();
  int hits = 0;
  int writes = 0;
  int get sizeBytes => _entries.values.fold(0, (sum, e) => sum + e.length);
  int get cacheBytes => _entries.entries
      .where((e) => !_protected.contains(e.key))
      .fold(0, (sum, e) => sum + e.value.length);
  StoredResource? find(String key) => _entries[key];

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

  Future<void> pin(String owner, String key) async {
    if (!_entries.containsKey(key)) throw StateError('Segment not committed');
    await metadata?.pin(owner, key);
    _protected.add(key);
  }

  Future<void> unpin(String owner) async {
    await metadata?.unpin(owner);
    _protected
      ..clear()
      ..addAll(await metadata?.protectedKeys() ?? {});
  }

  Future<void> verify(String key) async {
    final resource = _entries[key];
    if (resource == null ||
        !await resource.file.exists() ||
        '${await sha256.bind(resource.file.openRead()).first}' !=
            resource.digest) {
      throw const FileSystemException('离线分片缺失或损坏，请重新下载');
    }
  }

  Future<void> retainPins(String owner, Set<String> keys) async {
    await metadata?.retainPins(owner, keys);
    if (metadata != null) {
      final protected = await metadata!.protectedKeys();
      _protected
        ..clear()
        ..addAll(protected);
    }
  }

  Future<void> clearUnused() async {
    for (final key in _entries.keys.toList()) {
      if (_protected.contains(key) || _references.containsKey(key)) continue;
      final entry = _entries.remove(key)!;
      if (await entry.file.exists()) await entry.file.delete();
      await metadata?.remove(key);
    }
  }

  Future<ResourceLease> acquire(
    String key,
    Future<StoredResource> Function() load,
  ) async {
    _references.update(key, (value) => value + 1, ifAbsent: () => 1);
    try {
      var entry = _entries[key];
      if (entry != null && await entry.file.exists()) {
        hits++;
        _entries.remove(key);
        _entries[key] = entry;
      } else {
        final pending = _pending[key];
        if (pending != null) {
          hits++;
          entry = await pending;
        } else {
          final work = _load(key, load);
          _pending[key] = work;
          try {
            entry = await work;
          } finally {
            _pending.remove(key);
          }
        }
      }
      return ResourceLease(entry, () => _release(key));
    } catch (_) {
      _release(key);
      rethrow;
    }
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
        await sink.flush();
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
  ) async {
    final previous = _commits;
    final done = Completer<void>();
    _commits = done.future;
    await previous;
    try {
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
    } finally {
      done.complete();
    }
  }

  Future<void> _makeRoom(int bytes) async {
    // No awaits between reservation check and reference check; entries in use
    // are never removed. Serial gateway downloads are not assumed.
    for (final key in _entries.keys.toList()) {
      if (cacheBytes + bytes <= maxBytes) return;
      if (_references.containsKey(key) || _protected.contains(key)) continue;
      final entry = _entries.remove(key)!;
      if (await entry.file.exists()) await entry.file.delete();
      await metadata?.remove(key);
    }
    if (cacheBytes + bytes > maxBytes) {
      throw const FileSystemException('Cache is full with active resources');
    }
  }
}
