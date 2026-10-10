import 'dart:io';

import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/hive_cache_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anispark_cache_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('values and write times survive reopening the boxes', () async {
    final at = DateTime(2026, 10, 9, 12);
    final store = await HiveCacheStore.open();
    await store.write('v1|key', '{"t":1,"v":2}', at);
    await Hive.close();

    final reopened = await HiveCacheStore.open();

    expect(await reopened.read('v1|key'), '{"t":1,"v":2}');
    expect(reopened.writtenAt('v1|key'), at);
    expect(reopened.keys, ['v1|key']);
  });

  test('delete and clear remove values and write times', () async {
    final store = await HiveCacheStore.open();
    await store.write('a', 'x', DateTime(2026));
    await store.write('b', 'y', DateTime(2026));

    await store.delete('a');
    expect(await store.read('a'), isNull);
    expect(store.writtenAt('a'), isNull);

    await store.clear();
    expect(store.keys, isEmpty);
  });

  test('with a cipher, values are encrypted at rest and plaintext boxes are removed', () async {
    final legacy = await HiveCacheStore.open();
    await legacy.write('v1|old', 'personal data', DateTime(2026));
    await Hive.close();
    final cipher = HiveAesCipher(Hive.generateSecureKey());

    final store = await HiveCacheStore.open(cipher: cipher);
    await store.write('v1|k', 'value', DateTime(2026));
    await Hive.close();

    expect(await Hive.boxExists('api_cache'), isFalse);
    expect(await Hive.boxExists('api_cache_meta'), isFalse);
    final reopened = await HiveCacheStore.open(cipher: cipher);
    expect(await reopened.read('v1|k'), 'value');
    await Hive.close();
    // Opening without the key must not reveal the value (Hive discards it).
    final raw = await Hive.openLazyBox<String>('api_cache_v2');
    expect(await raw.get('v1|k'), isNull, reason: 'unreadable without the key');
  });

  test('works end to end through ApiCache', () async {
    final cache = ApiCache(await HiveCacheStore.open());

    await cache.write(ApiCache.userKey(1, 'list:ANIME'), {'CURRENT': []});

    expect((await cache.read(ApiCache.userKey(1, 'list:ANIME')))?.value, {'CURRENT': []});
    expect(await cache.read(ApiCache.userKey(2, 'list:ANIME')), isNull);
  });
}
