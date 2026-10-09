import 'dart:async';
import 'dart:convert';

import 'package:anispark/providers/media_list_store.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';

const _token = 'test-token';
const _userId = 7;

Map<String, dynamic> _entry(int mediaId, {int progress = 0, double score = 0}) => {
      'id': mediaId * 10,
      'mediaId': mediaId,
      'progress': progress,
      'score': score,
      'notes': null,
      'customLists': null,
      'media': {
        'id': mediaId,
        'title': {'romaji': 'Title $mediaId'},
        'episodes': 12,
      },
    };

Map<String, dynamic> _list(String status, List<Map<String, dynamic>> entries) =>
    {'name': status, 'status': status, 'isCustomList': false, 'entries': entries};

Map<String, dynamic> _customList(String name, List<Map<String, dynamic>> entries) =>
    {'name': name, 'status': null, 'isCustomList': true, 'entries': entries};

Map<String, dynamic> _collection(List<Map<String, dynamic>> lists) => {
      'data': {
        'MediaListCollection': {'lists': lists},
      },
    };

Map<String, dynamic> _saved(int mediaId, {required String status, required int progress, double score = 0}) => {
      'data': {
        'SaveMediaListEntry': {'id': mediaId * 10, 'status': status, 'progress': progress, 'score': score},
      },
    };

class _CountingCacheStore extends MemoryCacheStore {
  int writes = 0;

  @override
  Future<void> write(String key, String value, DateTime at) {
    writes++;
    return super.write(key, value, at);
  }
}

int _progressOf(MediaListStore store, String listKey, int mediaId) =>
    store.listsOf('ANIME')![listKey]!.firstWhere((e) => e['mediaId'] == mediaId)['progress'] as int;

void main() {
  late List<RecordedRequest> log;
  late ApiCache cache;
  late http.Response Function(RecordedRequest request) respond;

  MediaListStore buildStore({Duration persistDelay = Duration.zero}) => MediaListStore(
        service: AniListService(client: mockAniList(log, (r) => respond(r))),
        cache: cache,
        persistDelay: persistDelay,
      );

  setUp(() {
    log = [];
    cache = ApiCache(MemoryCacheStore());
    authExpiredNotifier.value = 0;
    respond = (_) => jsonResponse(_collection([
          _list('CURRENT', [_entry(1, progress: 3)]),
        ]));
  });

  group('load', () {
    test('shows the cached list first, then the fresh one', () async {
      await cache.write(ApiCache.userKey(_userId, 'list:ANIME'), {
        'CURRENT': [_entry(1, progress: 1)],
      });
      final store = buildStore();
      final seen = <int>[];
      store.addListener(() {
        final lists = store.listsOf('ANIME');
        if (lists != null) seen.add(lists['CURRENT']!.single['progress'] as int);
      });

      final gotFresh = await store.load('ANIME', userId: _userId, token: _token);

      expect(gotFresh, isTrue);
      expect(seen.first, 1);
      expect(seen.last, 3);
      expect(store.isLoading('ANIME'), isFalse);
    });

    test('sets an error when nothing is cached and the request fails', () async {
      respond = (_) => throw http.ClientException('offline');
      final store = buildStore();

      final gotFresh = await store.load('ANIME', userId: _userId, token: _token);

      expect(gotFresh, isFalse);
      expect(store.listsOf('ANIME'), isNull);
      expect(store.errorOf('ANIME'), isNotNull);
    });

    test('keeps showing cached data when the refresh fails', () async {
      await cache.write(ApiCache.userKey(_userId, 'list:ANIME'), {
        'CURRENT': [_entry(1, progress: 1)],
      });
      respond = (_) => throw http.ClientException('offline');
      final store = buildStore();

      await store.load('ANIME', userId: _userId, token: _token);

      expect(_progressOf(store, 'CURRENT', 1), 1);
    });

    test('drops the previous account data when the user changes', () async {
      final store = buildStore();
      await store.load('ANIME', userId: _userId, token: _token);
      respond = (_) => throw http.ClientException('offline');

      await store.load('ANIME', userId: 99, token: _token);

      expect(store.listsOf('ANIME'), isNull);
    });

    test('a late load for a previous account does not disturb the current one', () async {
      final gates = {7: Completer<void>(), 99: Completer<void>()};
      final store = MediaListStore(
        service: AniListService(
          client: MockClient((request) async {
            final variables = (jsonDecode(request.body) as Map)['variables'] as Map;
            final userId = variables['userId'] as int;
            await gates[userId]!.future;
            return jsonResponse(_collection([
              _list('CURRENT', [_entry(userId)]),
            ]));
          }),
        ),
        cache: cache,
        persistDelay: Duration.zero,
      );

      final first = store.load('ANIME', userId: 7, token: _token);
      await pumpEventQueue();
      final second = store.load('ANIME', userId: 99, token: _token);
      await pumpEventQueue();
      gates[7]!.complete();
      await first;

      expect(store.isLoading('ANIME'), isTrue);
      expect(store.listsOf('ANIME'), isNull);

      gates[99]!.complete();
      await second;
      expect(store.listsOf('ANIME')!['CURRENT']!.single['mediaId'], 99);
    });

    test('cached data never replaces lists already in memory', () async {
      final store = buildStore();
      await store.load('ANIME', userId: _userId, token: _token);
      await cache.write(ApiCache.userKey(_userId, 'list:ANIME'), {
        'CURRENT': [_entry(1, progress: 1)],
      });
      respond = (_) => throw http.ClientException('offline');

      await store.load('ANIME', userId: _userId, token: _token);

      expect(_progressOf(store, 'CURRENT', 1), 3);
    });

    test('a load requested while one is running runs again afterwards', () async {
      final store = buildStore();

      await Future.wait([
        store.load('ANIME', userId: _userId, token: _token),
        store.load('ANIME', userId: _userId, token: _token, force: true),
      ]);

      expect(log.where((r) => r.query.contains('MediaListCollection')), hasLength(2));
    });
  });

  group('setProgress', () {
    late MediaListStore store;

    setUp(() async {
      respond = (_) => jsonResponse(_collection([
            _list('CURRENT', [_entry(1, progress: 3, score: 7.5)]),
            _customList('Favs', [_entry(1, progress: 3, score: 7.5)]),
          ]));
      store = buildStore();
      await store.load('ANIME', userId: _userId, token: _token);
      log.clear();
    });

    test('updates every copy of the entry at once and saves only progress', () async {
      respond = (_) => jsonResponse(_saved(1, status: 'CURRENT', progress: 4, score: 7.5));

      final future = store.setProgress('ANIME', 1, 4, token: _token);

      expect(_progressOf(store, 'CURRENT', 1), 4);
      expect(_progressOf(store, 'custom:Favs', 1), 4);
      expect(store.isSaving(1), isTrue);
      expect(await future, isTrue);
      expect(log.single.variables, {'mediaId': 1, 'progress': 4});
      expect(store.isSaving(1), isFalse);
    });

    test('reverts and returns false when AniList rejects the change', () async {
      respond = (_) => jsonResponse({'data': {'SaveMediaListEntry': null}});

      final ok = await store.setProgress('ANIME', 1, 4, token: _token);

      expect(ok, isFalse);
      expect(_progressOf(store, 'CURRENT', 1), 3);
      expect(_progressOf(store, 'custom:Favs', 1), 3);
    });

    test('ignores a second change while the first is still saving', () async {
      respond = (_) => jsonResponse(_saved(1, status: 'CURRENT', progress: 4));

      final first = store.setProgress('ANIME', 1, 4, token: _token);
      final second = await store.setProgress('ANIME', 1, 5, token: _token);
      await first;

      expect(second, isFalse);
      expect(log, hasLength(1));
      expect(_progressOf(store, 'CURRENT', 1), 4);
    });

    test('moves the entry when AniList reports a new status', () async {
      respond = (_) => jsonResponse(_saved(1, status: 'COMPLETED', progress: 12, score: 9));

      final ok = await store.saveFields('ANIME', 1, status: 'COMPLETED', progress: 12, scoreRaw: 90, token: _token);

      expect(ok, isTrue);
      final lists = store.listsOf('ANIME')!;
      expect(lists['CURRENT'], isEmpty);
      expect(lists['COMPLETED']!.single['score'], 9);
      expect(lists['custom:Favs']!.single['progress'], 12);
    });

    test('persists the new state so the next launch shows it', () async {
      respond = (_) => jsonResponse(_saved(1, status: 'CURRENT', progress: 4));

      await store.setProgress('ANIME', 1, 4, token: _token);
      await pumpEventQueue();

      final cached = await cache.read(ApiCache.userKey(_userId, 'list:ANIME'));
      final current = (cached!.value as Map)['CURRENT'] as List;
      expect((current.single as Map)['progress'], 4);
    });
  });

  test('rapid edits are written to the cache once', () async {
    final counting = _CountingCacheStore();
    cache = ApiCache(counting);
    final store = buildStore(persistDelay: const Duration(milliseconds: 20));
    await store.load('ANIME', userId: _userId, token: _token);
    final writesAfterLoad = counting.writes;

    respond = (_) => jsonResponse(_saved(1, status: 'CURRENT', progress: 4));
    await store.setProgress('ANIME', 1, 4, token: _token);
    respond = (_) => jsonResponse(_saved(1, status: 'CURRENT', progress: 5));
    await store.setProgress('ANIME', 1, 5, token: _token);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(counting.writes - writesAfterLoad, 1);
    final cached = await cache.read(ApiCache.userKey(_userId, 'list:ANIME'));
    expect((((cached!.value as Map)['CURRENT'] as List).single as Map)['progress'], 5);
  });

  test('removeEntry deletes every copy of an entry', () async {
    respond = (_) => jsonResponse(_collection([
          _list('CURRENT', [_entry(1), _entry(2)]),
          _customList('Favs', [_entry(1)]),
        ]));
    final store = buildStore();
    await store.load('ANIME', userId: _userId, token: _token);

    store.removeEntry('ANIME', 1);

    final lists = store.listsOf('ANIME')!;
    expect(lists['CURRENT']!.map((e) => e['mediaId']), [2]);
    expect(lists['custom:Favs'], isEmpty);
  });

  test('reset forgets everything', () async {
    final store = buildStore();
    await store.load('ANIME', userId: _userId, token: _token);

    store.reset();

    expect(store.listsOf('ANIME'), isNull);
  });
}
