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

  test('works end to end through ApiCache', () async {
    final cache = ApiCache(await HiveCacheStore.open());

    await cache.write(ApiCache.userKey(1, 'list:ANIME'), {'CURRENT': []});

    expect((await cache.read(ApiCache.userKey(1, 'list:ANIME')))?.value, {'CURRENT': []});
    expect(await cache.read(ApiCache.userKey(2, 'list:ANIME')), isNull);
  });
}
