import 'package:hive/hive.dart';

import 'api_cache.dart';

/// [CacheStore] backed by Hive. Values live in a lazy box so large lists are
/// only read from disk when needed; write times live in a small in-memory box
/// so pruning never has to load the values.
class HiveCacheStore implements CacheStore {
  HiveCacheStore._(this._values, this._writtenAt);

  static Future<HiveCacheStore> open() async => HiveCacheStore._(
        await Hive.openLazyBox<String>('api_cache'),
        await Hive.openBox<int>('api_cache_meta'),
      );

  final LazyBox<String> _values;
  final Box<int> _writtenAt;

  @override
  Future<String?> read(String key) => _values.get(key);

  @override
  Future<void> write(String key, String value, DateTime at) async {
    await _values.put(key, value);
    await _writtenAt.put(key, at.millisecondsSinceEpoch);
  }

  @override
  Future<void> delete(String key) async {
    await _values.delete(key);
    await _writtenAt.delete(key);
  }

  @override
  Future<void> clear() async {
    await _values.clear();
    await _writtenAt.clear();
  }

  @override
  Iterable<String> get keys => _values.keys.cast<String>().toList();

  @override
  DateTime? writtenAt(String key) {
    final millis = _writtenAt.get(key);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
