import 'package:anispark/services/api_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_cache_store.dart';

void main() {
  late MemoryCacheStore store;
  late DateTime now;
  late ApiCache cache;

  setUp(() {
    store = MemoryCacheStore();
    now = DateTime(2026, 10, 9, 12);
    cache = ApiCache(store, clock: () => now);
  });

  List<String> decodeStrings(Object? json) => (json as List).cast<String>();

  group('read/write', () {
    test('returns null for a missing key', () async {
      expect(await cache.read('missing'), isNull);
    });

    test('returns the written value with the time it was saved', () async {
      await cache.write('k', {'a': 1});

      final cached = await cache.read('k');

      expect(cached?.value, {'a': 1});
      expect(cached?.savedAt, now);
    });

    test('drops a corrupted entry instead of failing', () async {
      await cache.write('k', 'ok');
      store.values[store.keys.single] = 'not json';

      expect(await cache.read('k'), isNull);
      expect(store.values, isEmpty);
    });

    test('clear removes everything', () async {
      await cache.write('a', 1);
      await cache.write('b', 2);

      await cache.clear();

      expect(await cache.read('a'), isNull);
      expect(await cache.read('b'), isNull);
    });
  });

  group('load (stale-while-revalidate)', () {
    test('without cache it fetches, stores and emits the fresh value', () async {
      final emitted = <(String, bool)>[];

      await cache.load<List<String>>(
        key: 'k',
        fetch: () async => ['fresh'],
        decode: decodeStrings,
        onData: (value, {required isFresh}) => emitted.add((value.join(","), isFresh)),
      );

      expect(emitted, [
        ('fresh', true),
      ]);
      expect((await cache.read('k'))?.value, ['fresh']);
    });

    test('with a stale cache it emits the cached value, then the fresh one', () async {
      await cache.write('k', ['old']);
      now = now.add(const Duration(hours: 2));
      final emitted = <(String, bool)>[];

      await cache.load<List<String>>(
        key: 'k',
        fetch: () async => ['new'],
        decode: decodeStrings,
        maxAge: const Duration(hours: 1),
        onData: (value, {required isFresh}) => emitted.add((value.join(","), isFresh)),
      );

      expect(emitted, [
        ('old', false),
        ('new', true),
      ]);
    });

    test('with a cache younger than maxAge it does not fetch', () async {
      await cache.write('k', ['recent']);
      now = now.add(const Duration(minutes: 10));
      var fetches = 0;
      final emitted = <List<String>>[];

      await cache.load<List<String>>(
        key: 'k',
        fetch: () async {
          fetches++;
          return ['new'];
        },
        decode: decodeStrings,
        maxAge: const Duration(hours: 1),
        onData: (value, {required isFresh}) => emitted.add(value),
      );

      expect(fetches, 0);
      expect(emitted, [
        ['recent'],
      ]);
    });

    test('force skips the cache entirely', () async {
      await cache.write('k', ['recent']);
      final emitted = <List<String>>[];

      await cache.load<List<String>>(
        key: 'k',
        fetch: () async => ['new'],
        decode: decodeStrings,
        maxAge: const Duration(hours: 1),
        force: true,
        onData: (value, {required isFresh}) => emitted.add(value),
      );

      expect(emitted, [
        ['new'],
      ]);
    });

    test('an invalid fresh value is neither stored nor emitted', () async {
      await cache.write('k', ['good']);
      now = now.add(const Duration(hours: 2));
      final emitted = <List<String>>[];

      await cache.load<List<String>>(
        key: 'k',
        fetch: () async => <String>[],
        decode: decodeStrings,
        isValid: (value) => value.isNotEmpty,
        onData: (value, {required isFresh}) => emitted.add(value),
      );

      expect(emitted, [
        ['good'],
      ]);
      expect((await cache.read('k'))?.value, ['good']);
    });

    test('a failed fetch is rethrown after the cached value was emitted', () async {
      await cache.write('k', ['cached']);
      final emitted = <List<String>>[];

      final future = cache.load<List<String>>(
        key: 'k',
        fetch: () async => throw Exception('offline'),
        decode: decodeStrings,
        onData: (value, {required isFresh}) => emitted.add(value),
      );

      await expectLater(future, throwsException);
      expect(emitted, [
        ['cached'],
      ]);
    });

    test('a cached value with an unexpected shape is treated as a miss', () async {
      await cache.write('k', {'not': 'a list'});
      final emitted = <(String, bool)>[];

      await cache.load<List<String>>(
        key: 'k',
        fetch: () async => ['fresh'],
        decode: decodeStrings,
        onData: (value, {required isFresh}) => emitted.add((value.join(","), isFresh)),
      );

      expect(emitted, [
        ('fresh', true),
      ]);
    });
  });

  group('prune', () {
    test('removes entries older than maxAge', () async {
      await cache.write('old', 1);
      now = now.add(const Duration(days: 20));
      await cache.write('new', 2);

      await cache.prune(maxAge: const Duration(days: 14), maxEntries: 100);

      expect(await cache.read('old'), isNull);
      expect(await cache.read('new'), isNotNull);
    });

    test('keeps only the newest maxEntries entries', () async {
      for (var i = 0; i < 5; i++) {
        await cache.write('k$i', i);
        now = now.add(const Duration(minutes: 1));
      }

      await cache.prune(maxAge: const Duration(days: 14), maxEntries: 2);

      expect(store.keys, hasLength(2));
      expect(await cache.read('k4'), isNotNull);
      expect(await cache.read('k3'), isNotNull);
    });

    test('removes entries written by an older cache format', () async {
      await store.write('v0|legacy', '{"t":0,"v":1}', now);
      await cache.write('current', 1);

      await cache.prune(maxAge: const Duration(days: 14), maxEntries: 100);

      expect(store.keys, hasLength(1));
      expect(await cache.read('current'), isNotNull);
    });
  });

  test('userKey namespaces keys per account', () {
    expect(ApiCache.userKey(7, 'list:ANIME'), isNot(ApiCache.userKey(8, 'list:ANIME')));
  });
}
