import 'dart:convert';

import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/browse_api.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/mock_anilist.dart';

Map<String, dynamic> _media(int id, {int? score = 80, String type = 'ANIME'}) => {
      'id': id,
      'type': type,
      'format': 'TV',
      'episodes': 12,
      'chapters': null,
      'averageScore': score,
      'title': {'romaji': 'Show $id', 'english': null, 'native': null},
      'coverImage': {'large': 'https://img/$id.jpg'},
    };

Map<String, dynamic> _page(List<Object?> media, {Object? hasNextPage = false}) => {
      'data': {
        'Page': {
          'pageInfo': {'hasNextPage': hasNextPage},
          'media': media,
        },
      },
    };

void main() {
  late List<RecordedRequest> log;
  final today = DateTime(2026, 10, 13, 18, 30);

  setUp(() {
    log = [];
    authExpiredNotifier.value = 0;
    rateLimitActiveNotifier.value = false;
  });

  BrowseApi apiAnswering(http.Response Function(RecordedRequest request) handler) =>
      BrowseApi(service: AniListService(client: mockAniList(log, handler)), clock: () => today);

  BrowseApi apiReturning(Object body, {int status = 200}) =>
      apiAnswering((_) => jsonResponse(body, status: status));

  group('BrowseQuery', () {
    test('each Discover row keeps the fixed filters of its own query', () {
      expect(BrowseQuery.trending.type, 'ANIME');
      expect(BrowseQuery.trending.sort, 'TRENDING_DESC');
      expect(BrowseQuery.topAiring.status, 'RELEASING');
      expect(BrowseQuery.topAiring.sort, 'POPULARITY_DESC');
      expect(BrowseQuery.trendingManga.formatNot, 'NOVEL');
      expect(BrowseQuery.trendingManga.sort, 'TRENDING_DESC');
      expect(BrowseQuery.topManga.formatNot, 'NOVEL');
      expect(BrowseQuery.topManga.sort, 'SCORE_DESC');
      expect(BrowseQuery.manhwa.countryOfOrigin, 'KR');
      expect(BrowseQuery.manhwa.sort, 'POPULARITY_DESC');
      for (final row in BrowseQuery.rows) {
        expect(row.isDefault, isTrue, reason: '${row.id} starts without user filters');
      }
      expect(BrowseQuery.rows.map((row) => row.id).toSet(), hasLength(BrowseQuery.rows.length));
    });

    test('copyWith changes only the user filters and keeps the row', () {
      final filtered = BrowseQuery.topAiring.copyWith(
        sort: 'SCORE_DESC',
        genres: {'Action'},
        formats: {'MOVIE'},
        minScore: 70,
      );

      expect(filtered.id, 'topAiring');
      expect(filtered.status, 'RELEASING');
      expect(filtered.defaultSort, 'POPULARITY_DESC');
      expect(filtered.sort, 'SCORE_DESC');
      expect(filtered.genres, {'Action'});
      expect(filtered.formats, {'MOVIE'});
      expect(filtered.minScore, 70);
      expect(filtered.isDefault, isFalse);
      expect(filtered.defaults, BrowseQuery.topAiring);
    });

    test('copyWith keeps its own copy of the sets it is given', () {
      final genres = {'Action'};
      final query = BrowseQuery.trending.copyWith(genres: genres);
      genres.add('Drama');

      expect(query.genres, {'Action'});
      expect(() => query.genres.add('Horror'), throwsUnsupportedError);
    });

    test('has value equality, whatever the order the sets were filled in', () {
      final a = BrowseQuery.trending.copyWith(genres: {'Action', 'Drama'}, formats: {'TV', 'OVA'});
      final b = BrowseQuery.trending.copyWith(genres: {'Drama', 'Action'}, formats: {'OVA', 'TV'});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.filterKey, b.filterKey);
      expect(a, isNot(BrowseQuery.trending));
      expect(a.copyWith(minScore: 60), isNot(a));
      expect(BrowseQuery.trending.copyWith(sort: 'TRENDING_DESC'), BrowseQuery.trending);
    });

    test('a different filter set has a different filter key', () {
      final keys = {
        BrowseQuery.trending.filterKey,
        BrowseQuery.trending.copyWith(sort: 'SCORE_DESC').filterKey,
        BrowseQuery.trending.copyWith(genres: {'Action'}).filterKey,
        BrowseQuery.trending.copyWith(formats: {'MOVIE'}).filterKey,
        BrowseQuery.trending.copyWith(minScore: 70).filterKey,
      };
      expect(keys, hasLength(5));
    });
  });

  group('browse', () {
    test('sends only the row filters and the default sort with an ID tiebreaker', () async {
      final api = apiReturning(_page([]));

      await api.browse(BrowseQuery.trending);

      expect(log.single.variables, {
        'page': 1,
        'perPage': BrowseApi.pageSize,
        'type': 'ANIME',
        'sort': ['TRENDING_DESC', 'ID'],
      });
      expect(log.single.authorization, isNull);
      expect(log.single.query, contains('isAdult: false'));
      expect(log.single.query, contains('pageInfo { hasNextPage }'));
    });

    test('sends the fixed filters of each row', () async {
      final api = apiReturning(_page([]));

      await api.browse(BrowseQuery.topAiring);
      await api.browse(BrowseQuery.trendingManga);
      await api.browse(BrowseQuery.manhwa);

      expect(log[0].variables, containsPair('status', 'RELEASING'));
      expect(log[0].variables['sort'], ['POPULARITY_DESC', 'ID']);
      expect(log[1].variables, containsPair('type', 'MANGA'));
      expect(log[1].variables, containsPair('format_not', 'NOVEL'));
      expect(log[2].variables, containsPair('countryOfOrigin', 'KR'));
      expect(log[2].variables.containsKey('format_not'), isFalse);
      for (final request in log) {
        expect(request.variables.keys,
            isNot(anyOf(contains('genre_in'), contains('format_in'), contains('averageScore_greater'))));
      }
    });

    test('sends the user filters, formats sorted, and the page asked for', () async {
      final api = apiReturning(_page([]));
      final query = BrowseQuery.trending.copyWith(
        sort: 'SCORE_DESC',
        genres: {'Drama', 'Action'},
        formats: {'TV', 'MOVIE', 'OVA'},
        minScore: 70,
      );

      await api.browse(query, page: 3);

      final variables = log.single.variables;
      expect(variables['page'], 3);
      expect(variables['sort'], ['SCORE_DESC', 'ID']);
      expect(variables['genre_in'], unorderedEquals(['Action', 'Drama']));
      expect(variables['format_in'], ['MOVIE', 'OVA', 'TV']);
      expect(variables['averageScore_greater'], 69);
    });

    test('never sends null variables (AniList answers format_in: null with a 500)', () async {
      final api = apiReturning(_page([]));

      await api.browse(BrowseQuery.topManga.copyWith(minScore: 0, genres: {}, formats: {}));

      expect(log.single.variables.values, isNot(contains(isNull)));
      expect(jsonEncode(log.single.body['variables']), isNot(contains('null')));
    });

    test('the rating options send the threshold just below them', () async {
      final api = apiReturning(_page([]));

      for (final score in [60, 70, 80]) {
        await api.browse(BrowseQuery.trending.copyWith(minScore: score));
      }

      expect(log.map((r) => r.variables['averageScore_greater']), [59, 69, 79]);
    });

    test('newest only lists titles that have started, newest first', () async {
      final api = apiReturning(_page([]));

      await api.browse(BrowseQuery.trending.copyWith(sort: 'START_DATE_DESC'));

      final variables = log.single.variables;
      expect(variables['sort'], ['START_DATE_DESC', 'ID']);
      // AniList puts titles without a date first; any real date is later.
      expect(variables['startDate_greater'], BrowseQuery.anyStartDate);
      // Up to today (13 Oct 2026), not titles announced for later.
      expect(variables['startDate_lesser'], 20261014);
    });

    test('other sorts send no start date window', () async {
      final api = apiReturning(_page([]));

      await api.browse(BrowseQuery.trending.copyWith(sort: 'POPULARITY_DESC'));

      expect(log.single.variables.keys, isNot(contains('startDate_greater')));
      expect(log.single.variables.keys, isNot(contains('startDate_lesser')));
    });

    test('parses the media and whether more pages follow', () async {
      final api = apiReturning(_page([_media(1), _media(2)], hasNextPage: true));

      final page = await api.browse(BrowseQuery.trending);

      expect(page.media.map((m) => m['id']), [1, 2]);
      expect(page.hasNextPage, isTrue);
      expect(page.media.first, {
        'id': 1,
        'type': 'ANIME',
        'format': 'TV',
        'episodes': 12,
        'averageScore': 80,
        'title': {'romaji': 'Show 1'},
        'coverImage': {'large': 'https://img/1.jpg'},
      });
      expect(() => page.media.add({}), throwsUnsupportedError);
    });

    test('hasNextPage is false when AniList says so or leaves it out', () async {
      final api = apiAnswering((request) => switch (request.variables['page']) {
            1 => jsonResponse(_page([_media(1)])),
            _ => jsonResponse({
                'data': {
                  'Page': {'media': [_media(2)]},
                },
              }),
          });

      expect((await api.browse(BrowseQuery.trending)).hasNextPage, isFalse);
      expect((await api.browse(BrowseQuery.trending, page: 2)).hasNextPage, isFalse);
    });

    test('an empty page ends the list even if AniList reports more', () async {
      final api = apiReturning(_page([], hasNextPage: true));

      final page = await api.browse(BrowseQuery.trending);

      expect(page.media, isEmpty);
      expect(page.hasNextPage, isFalse);
    });

    test('skips malformed items and keeps paging past them', () async {
      final api = apiReturning(_page([
        _media(1),
        'not a map',
        null,
        {'id': 'two', 'title': {'romaji': 'Bad id'}},
        {'title': {'romaji': 'No id'}},
        {
          'id': 3,
          'type': 7,
          'format': ['TV'],
          'episodes': '12',
          'averageScore': 'high',
          'title': 'Just a string',
          'coverImage': {'large': 42},
        },
      ], hasNextPage: true));

      final page = await api.browse(BrowseQuery.trending);

      expect(page.media.map((m) => m['id']), [1, 3]);
      // Fields of the wrong type are dropped; the row's type fills in.
      expect(page.media.last, {'id': 3, 'type': 'ANIME'});
      expect(page.hasNextPage, isTrue);
    });

    test('a manga without a type in the response is still a manga', () async {
      final media = _media(5, type: 'MANGA')..remove('type');
      final api = apiReturning(_page([media]));

      final page = await api.browse(BrowseQuery.topManga);

      expect(page.media.single['type'], 'MANGA');
    });

    test('drops titles shown below the minimum rating', () async {
      // AniList compares the unrounded score, so `averageScore_greater: 69`
      // also returns titles at 69.4, which it reports (and the app shows) as 69.
      final api = apiReturning(_page([_media(1, score: 85), _media(2, score: 69), _media(3, score: 70)]));

      final page = await api.browse(BrowseQuery.trending.copyWith(minScore: 70));

      expect(page.media.map((m) => m['id']), [1, 3]);
    });

    test('keeps unscored titles when no rating is asked for', () async {
      final api = apiReturning(_page([_media(1, score: null)]));

      final page = await api.browse(BrowseQuery.trending);

      expect(page.media.single['id'], 1);
      expect(page.media.single.containsKey('averageScore'), isFalse);
    });

    test('throws on an unexpected response shape', () async {
      final api = apiReturning({
        'data': {'Page': null},
      });

      await expectLater(api.browse(BrowseQuery.trending), throwsFormatException);
    });

    test('throws AniListRequestException on HTTP errors', () async {
      final api = apiReturning({'errors': [{'message': 'boom'}]}, status: 500);

      await expectLater(
        api.browse(BrowseQuery.trending),
        throwsA(isA<AniListRequestException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });

  group('BrowsePage JSON', () {
    test('round-trips through JSON for the cache', () async {
      final api = apiReturning(_page([_media(1), _media(2)], hasNextPage: true));
      final page = await api.browse(BrowseQuery.trending);

      final restored = BrowsePage.fromJson(jsonDecode(jsonEncode(page.toJson())));

      expect(restored.media, page.media);
      expect(restored.hasNextPage, isTrue);
    });

    test('skips malformed cached items', () {
      final restored = BrowsePage.fromJson({
        'media': [
          {'id': 1, 'type': 'MANGA'},
          'oops',
          {'id': null},
        ],
        'hasNextPage': false,
      });

      expect(restored.media, [
        {'id': 1, 'type': 'MANGA'},
      ]);
    });

    test('rejects data of another shape', () {
      expect(() => BrowsePage.fromJson(null), throwsFormatException);
      expect(() => BrowsePage.fromJson([1, 2]), throwsFormatException);
      expect(() => BrowsePage.fromJson({'media': 'nope', 'hasNextPage': true}), throwsFormatException);
      expect(() => BrowsePage.fromJson({'media': [], 'hasNextPage': 'yes'}), throwsFormatException);
    });
  });
}
