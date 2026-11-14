import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/poster_repository.dart';

typedef BookCoverCacheUsage = ({int entries, int bytes, int limitBytes});

final class BookCoverCache extends ChangeNotifier {
  BookCoverCache(this.directory, {int maxMiB = 32})
    : _maxBytes = maxMiB * 1024 * 1024;

  final Directory directory;
  final Map<String, _CoverEntry> _entries = {};
  final Map<String, Uint8List> _memory = {};
  Future<void> _queue = Future.value();
  int _maxBytes;
  int _memoryBytes = 0;
  int _generation = 0;
  bool _loaded = false;

  int get generation => _generation;
  int get limitBytes => _maxBytes;
  Future<void> waitForIdle() => _queue;

  String key(String title, String author, Uri cover) =>
      sha256.convert(utf8.encode('$title\u0000$author\u0000$cover')).toString();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _load() async {
    if (_loaded) return;
    if (!await directory.exists()) {
      _loaded = true;
      return;
    }
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!RegExp(r'^[0-9a-f]{64}\.img$').hasMatch(name)) continue;
      final stat = await entity.stat();
      _entries[name.substring(0, 64)] = _CoverEntry(stat.size, stat.modified);
    }
    await _prune();
    _loaded = true;
  }

  File _file(String key) => File('${directory.path}/$key.img');

  Future<Uint8List?> read(String key) => _serial(() async {
    if (_maxBytes == 0) return null;
    await _load();
    final entry = _entries[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.created) > const Duration(days: 7) ||
        entry.bytes > 2 * 1024 * 1024) {
      await _remove(key);
      return null;
    }
    final memory = _memory.remove(key);
    if (memory != null) {
      _memory[key] = memory;
      entry.lastUsed = DateTime.now();
      return memory;
    }
    try {
      final bytes = await _file(key).readAsBytes();
      if (bytes.length != entry.bytes || !isPosterPayload(bytes)) {
        await _remove(key);
        return null;
      }
      entry.lastUsed = DateTime.now();
      _remember(key, bytes);
      return bytes;
    } on FileSystemException {
      _entries.remove(key);
      return null;
    }
  });

  Future<void> write(String key, List<int> bytes, int generation) =>
      _serial(() async {
        if (generation != _generation ||
            _maxBytes == 0 ||
            bytes.length > 2 * 1024 * 1024 ||
            !isPosterPayload(bytes)) {
          return;
        }
        await _load();
        await directory.create(recursive: true);
        final file = _file(key);
        await file.writeAsBytes(bytes, flush: true);
        _entries[key] = _CoverEntry(bytes.length, DateTime.now());
        _remember(key, Uint8List.fromList(bytes));
        await _prune();
        notifyListeners();
      });

  Future<BookCoverCacheUsage> usage() => _serial(() async {
    await _load();
    return (
      entries: _entries.length,
      bytes: _entries.values.fold<int>(0, (sum, entry) => sum + entry.bytes),
      limitBytes: _maxBytes,
    );
  });

  Future<void> setMaxMiB(int value) {
    _maxBytes = value * 1024 * 1024;
    if (value == 0) _generation++;
    return _serial(() async {
      await _load();
      await _prune();
      _pruneMemory();
      notifyListeners();
    });
  }

  Future<void> clear() {
    _generation++;
    return _serial(() async {
      await _load();
      for (final key in _entries.keys.toList()) {
        await _remove(key, strict: true);
      }
      _memory.clear();
      _memoryBytes = 0;
      notifyListeners();
    });
  }

  Future<void> _prune() async {
    var total = _entries.values.fold<int>(0, (sum, entry) => sum + entry.bytes);
    final oldest = _entries.entries.toList()
      ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    for (final entry in oldest) {
      if (total <= _maxBytes && _entries.length <= 512) break;
      await _remove(entry.key);
      if (!_entries.containsKey(entry.key)) total -= entry.value.bytes;
    }
  }

  Future<void> _remove(String key, {bool strict = false}) async {
    final file = _file(key);
    try {
      await file.delete();
    } on FileSystemException {
      if (await file.exists()) {
        if (strict) rethrow;
        return;
      }
    }
    _entries.remove(key);
    final memory = _memory.remove(key);
    if (memory != null) _memoryBytes -= memory.length;
  }

  void _remember(String key, Uint8List bytes) {
    final old = _memory.remove(key);
    if (old != null) _memoryBytes -= old.length;
    _memory[key] = bytes;
    _memoryBytes += bytes.length;
    _pruneMemory();
  }

  void _pruneMemory() {
    final limit = _maxBytes < 8 * 1024 * 1024 ? _maxBytes : 8 * 1024 * 1024;
    while (_memoryBytes > limit || _memory.length > 80) {
      _memoryBytes -= _memory.remove(_memory.keys.first)!.length;
    }
  }
}

final class _CoverEntry {
  _CoverEntry(this.bytes, this.created) : lastUsed = created;
  final int bytes;
  final DateTime created;
  DateTime lastUsed;
}
