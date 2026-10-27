import 'segment_store.dart';

abstract interface class SegmentMetadata {
  Future<Map<String, StoredResource>> entries();
  Future<void> put(String key, StoredResource value);
  Future<void> remove(String key);
  Future<Set<String>> protectedKeys();
  Future<void> pin(String owner, String key);
  Future<void> unpin(String owner);
  Future<void> retainPins(String owner, Set<String> keys);
}
