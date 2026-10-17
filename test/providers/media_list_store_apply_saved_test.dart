import 'package:anispark/providers/media_list_store.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';

Map<String, dynamic> _entry(int mediaId, {int progress = 0, double score = 0, String? notes}) => {
      'id': mediaId * 10,
      'mediaId': mediaId,
      'progress': progress,
      'score': score,
      'notes': notes,
      'customLists': null,
      'media': {'id': mediaId, 'title': {'romaji': 'Title $mediaId'}, 'episodes': 12},
    };

void main() {
  late List<RecordedRequest> log;
  late MediaListStore store;

  setUp(() async {
    log = [];
    store = MediaListStore(
      service: AniListService(
        client: mockAniList(
          log,
          (_) => jsonResponse({
            'data': {
              'MediaListCollection': {
                'lists': [
                  {'name': 'Watching', 'status': 'CURRENT', 'isCustomList': false, 'entries': [_entry(1, progress: 3)]},
                  {'name': 'Favs', 'status': null, 'isCustomList': true, 'entries': [_entry(1, progress: 3)]},
                  {'name': 'Planning', 'status': 'PLANNING', 'isCustomList': false, 'entries': [_entry(2)]},
                ],
              },
            },
          }),
        ),
      ),
      cache: ApiCache(MemoryCacheStore()),
      persistDelay: Duration.zero,
    );
    await store.load('ANIME', userId: 7, token: 'token');
    log.clear();
  });

  tearDown(() => store.dispose());

  test('applySavedEntry updates every copy of the entry without a request', () {
    var notified = 0;
    store.addListener(() => notified++);

    store.applySavedEntry('ANIME', 1, {
      'id': 10,
      'status': 'CURRENT',
      'progress': 7,
      'score': 8.5,
      'notes': 'great',
    });

    final lists = store.listsOf('ANIME')!;
    for (final key in ['CURRENT', '${customListPrefix}Favs']) {
      final entry = lists[key]!.single;
      expect(entry['progress'], 7, reason: key);
      expect(entry['score'], 8.5, reason: key);
      expect(entry['notes'], 'great', reason: key);
      expect(entry['media'], isNotNull, reason: 'the media must be kept');
    }
    expect(notified, greaterThan(0));
    expect(log, isEmpty);
  });

  test('applySavedEntry moves the entry when its status changed', () {
    store.applySavedEntry('ANIME', 2, {'id': 20, 'status': 'CURRENT', 'progress': 1});

    final lists = store.listsOf('ANIME')!;
    expect(lists['PLANNING'], isEmpty);
    expect(lists['CURRENT']!.map((e) => e['mediaId']), [2, 1]);
  });

  test('applySavedEntry ignores an entry that is not in the loaded list', () {
    final before = store.listsOf('ANIME');

    store.applySavedEntry('ANIME', 99, {'id': 990, 'status': 'PLANNING', 'progress': 0});
    store.applySavedEntry('MANGA', 1, {'id': 10, 'status': 'PLANNING', 'progress': 0});

    expect(store.listsOf('ANIME'), same(before));
    expect(store.listsOf('MANGA'), isNull);
  });
}
