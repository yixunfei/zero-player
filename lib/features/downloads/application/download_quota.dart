import 'dart:io';

/// Shared synchronous accounting prevents parallel episodes spending the same
/// free bytes. A reservation is made before writing/pinning each payload.
final class DownloadQuota {
  final Map<String, int> _usage = {};
  void initialize(Map<String, int> bytes) {
    _usage.clear();
    _usage.addAll(bytes);
  }

  void reserve(String id, int bytes, int limit) {
    if ((_usage[id] ?? 0) > bytes) bytes = _usage[id]!;
    final total = _usage.entries
        .where((e) => e.key != id)
        .fold(0, (sum, e) => sum + e.value);
    if (total + bytes > limit) throw const FileSystemException('离线下载容量已用完');
    _usage[id] = bytes;
  }

  void release(String id) => _usage.remove(id);
}
