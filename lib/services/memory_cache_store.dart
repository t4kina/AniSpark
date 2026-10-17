import 'api_cache.dart';

/// In-memory [CacheStore]: used in tests, and as a fallback when the disk
/// cache can't be opened so the app still starts.
class MemoryCacheStore implements CacheStore {
  final Map<String, String> values = {};
  final Map<String, DateTime> _writtenAt = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value, DateTime at) async {
    values[key] = value;
    _writtenAt[key] = at;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
    _writtenAt.remove(key);
  }

  @override
  Future<void> clear() async {
    values.clear();
    _writtenAt.clear();
  }

  @override
  Iterable<String> get keys => values.keys.toList();

  @override
  DateTime? writtenAt(String key) => _writtenAt[key];
}
