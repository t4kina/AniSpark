import 'dart:convert';

/// Persistent key/value storage used by [ApiCache].
abstract interface class CacheStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value, DateTime at);
  Future<void> delete(String key);
  Future<void> clear();
  Iterable<String> get keys;
  DateTime? writtenAt(String key);
}

/// A cached JSON value and when it was saved.
class CachedValue {
  const CachedValue(this.value, this.savedAt);

  final Object? value;
  final DateTime savedAt;
}

typedef CacheDataCallback<T> = void Function(T value, {required bool isFresh});

/// Disk cache for AniList responses so screens can show the last known data
/// instantly and refresh it in the background (stale-while-revalidate).
///
/// Never store tokens here, and namespace anything account-specific with
/// [userKey]. The whole cache is cleared on logout.
class ApiCache {
  ApiCache(this._store, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  // Bump when the shape of cached data changes; older entries are pruned.
  static const _version = 'v1';

  final CacheStore _store;
  final DateTime Function() _now;
  // Bumped by clear() so responses that were in flight during a logout are
  // not written back to disk afterwards.
  int _generation = 0;

  static String userKey(int userId, String name) => 'u$userId:$name';

  String _storeKey(String key) => '$_version|$key';

  Future<CachedValue?> read(String key) async {
    final storeKey = _storeKey(key);
    final raw = await _store.read(storeKey);
    if (raw == null) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      decoded = null;
    }
    if (decoded case {'t': final int savedAt, 'v': final value}) {
      return CachedValue(value, DateTime.fromMillisecondsSinceEpoch(savedAt));
    }
    await _store.delete(storeKey);
    return null;
  }

  Future<void> write(String key, Object? value) {
    final now = _now();
    return _store.write(
      _storeKey(key),
      jsonEncode({'t': now.millisecondsSinceEpoch, 'v': value}),
      now,
    );
  }

  Future<void> remove(String key) => _store.delete(_storeKey(key));

  Future<void> clear() {
    _generation++;
    return _store.clear();
  }

  /// Emits the cached value (if any) through [onData], then fetches a fresh
  /// one unless the cached copy is younger than [maxAge]. Fresh values that
  /// fail [isValid] (e.g. an empty list returned after an API error) are
  /// discarded so they never replace good cached data. Fetch errors are
  /// rethrown; any cached value has already been emitted by then.
  Future<void> load<T>({
    required String key,
    required Future<T> Function() fetch,
    required T Function(Object? json) decode,
    required CacheDataCallback<T> onData,
    Duration maxAge = Duration.zero,
    bool force = false,
    bool Function(T value)? isValid,
  }) async {
    final generation = _generation;
    if (!force) {
      final cached = await read(key);
      final decoded = cached == null ? null : _tryDecode(cached.value, decode);
      if (cached != null && decoded != null) {
        onData(decoded.$1, isFresh: false);
        final age = _now().difference(cached.savedAt);
        if (!age.isNegative && age < maxAge) return;
      }
    }
    final fresh = await fetch();
    if (isValid != null && !isValid(fresh)) return;
    onData(fresh, isFresh: true);
    if (generation == _generation) await write(key, fresh);
  }

  (T,)? _tryDecode<T>(Object? json, T Function(Object? json) decode) {
    try {
      return (decode(json),);
    } on Object {
      // Persisted data that doesn't decode (e.g. saved before a change in
      // its shape) is treated as a cache miss rather than breaking the screen.
      return null;
    }
  }

  /// Deletes entries older than [maxAge], entries from older cache versions,
  /// and the oldest entries beyond [maxEntries].
  Future<void> prune({required Duration maxAge, required int maxEntries}) async {
    final now = _now();
    final kept = <(String, DateTime)>[];
    for (final key in _store.keys.toList()) {
      final writtenAt = _store.writtenAt(key);
      final expired = writtenAt == null || now.difference(writtenAt) > maxAge;
      if (expired || !key.startsWith('$_version|')) {
        await _store.delete(key);
      } else {
        kept.add((key, writtenAt));
      }
    }
    if (kept.length <= maxEntries) return;
    kept.sort((a, b) => b.$2.compareTo(a.$2));
    for (final (key, _) in kept.skip(maxEntries)) {
      await _store.delete(key);
    }
  }
}
