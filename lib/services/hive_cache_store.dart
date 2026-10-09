import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive/hive.dart';

import 'api_cache.dart';
import 'memory_cache_store.dart';

/// [CacheStore] backed by Hive. Values live in a lazy box so large lists are
/// only read from disk when needed; write times live in a small in-memory box
/// so pruning never has to load the values.
class HiveCacheStore implements CacheStore {
  HiveCacheStore._(this._values, this._writtenAt);

  static Future<HiveCacheStore> open() async => HiveCacheStore._(
        await Hive.openLazyBox<String>('api_cache'),
        await Hive.openBox<int>('api_cache_meta'),
      );

  /// Opens the disk cache, recreating it if it can't be opened (e.g. a
  /// corrupted file), and falls back to an in-memory cache as a last resort:
  /// a cache problem must never stop the app from starting.
  static Future<CacheStore> openOrFallback() async {
    // Hive reports unreadable boxes as HiveError (an Error), so catch broadly.
    try {
      return await open();
    } on Object catch (e) {
      debugPrint('[Cache] Opening the disk cache failed, recreating it: $e');
    }
    try {
      await Hive.deleteBoxFromDisk('api_cache');
      await Hive.deleteBoxFromDisk('api_cache_meta');
      return await open();
    } on Object catch (e) {
      debugPrint('[Cache] Using an in-memory cache instead: $e');
      return MemoryCacheStore();
    }
  }

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
