import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_anilist.dart';

/// Mirrors the "YYYY-MM-DD" key format produced by
/// [AniListService.getUserActivityDays] so tests can derive the expected
/// key from a timestamp instead of hard-coding dates (avoids midnight
/// boundary flakiness).
String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  const token = 'test-token';
  late List<RecordedRequest> log;

  setUp(() {
    log = [];
    authExpiredNotifier.value = 0;
    rateLimitActiveNotifier.value = false;
  });

  AniListService serviceReturning(Object body, {int status = 200}) =>
      AniListService(
        client: mockAniList(log, (_) => jsonResponse(body, status: status)),
      );

  group('getUserAnimeList', () {
    test('sends the userId variable and Authorization bearer header',
        () async {
      final service = serviceReturning({
        'data': {
          'MediaListCollection': {'lists': <dynamic>[]},
        },
      });

      await service.getUserAnimeList(42, token);

      expect(log.single.variables, {'userId': 42});
      expect(log.single.authorization, 'Bearer $token');
    });

    test(
        'maps standard lists by status and custom lists by custom:<name>',
        () async {
      final service = serviceReturning({
        'data': {
          'MediaListCollection': {
            'lists': [
              {
                'name': 'Watching',
                'status': 'CURRENT',
                'isCustomList': false,
                'entries': [
                  {'id': 1, 'mediaId': 10, 'progress': 3},
                ],
              },
              {
                'name': 'My Favorites',
                'status': null,
                'isCustomList': true,
                'entries': [
                  {'id': 2, 'mediaId': 20, 'progress': 0},
                ],
              },
            ],
          },
        },
      });

      final result = await service.getUserAnimeList(1, token);

      expect(result.keys, containsAll(['CURRENT', 'custom:My Favorites']));
      expect(result['CURRENT'], [
        {'id': 1, 'mediaId': 10, 'progress': 3},
      ]);
      expect(result['custom:My Favorites'], [
        {'id': 2, 'mediaId': 20, 'progress': 0},
      ]);
    });

    test('throws an Exception on a non-200 response', () async {
      final service = serviceReturning({}, status: 500);

      await expectLater(
        () => service.getUserAnimeList(1, token),
        throwsA(isA<Exception>()),
      );
    });

    test('throws an Exception and increments authExpiredNotifier on 401',
        () async {
      final service = serviceReturning({}, status: 401);

      await expectLater(
        () => service.getUserAnimeList(1, token),
        throwsA(isA<Exception>()),
      );
      expect(authExpiredNotifier.value, 1);
    });

    test('throws an Exception when the lists field is missing', () async {
      final service = serviceReturning({
        'data': {'MediaListCollection': {}},
      });

      await expectLater(
        () => service.getUserAnimeList(1, token),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('getUserMangaList', () {
    test('sends the userId variable and Authorization bearer header',
        () async {
      final service = serviceReturning({
        'data': {
          'MediaListCollection': {'lists': <dynamic>[]},
        },
      });

      await service.getUserMangaList(7, token);

      expect(log.single.variables, {'userId': 7});
      expect(log.single.authorization, 'Bearer $token');
    });

    test(
        'maps standard lists by status and custom lists by custom:<name>',
        () async {
      final service = serviceReturning({
        'data': {
          'MediaListCollection': {
            'lists': [
              {
                'name': 'Reading',
                'status': 'CURRENT',
                'isCustomList': false,
                'entries': [
                  {'id': 1, 'mediaId': 11, 'progress': 4},
                ],
              },
              {
                'name': 'Must Reread',
                'status': null,
                'isCustomList': true,
                'entries': [
                  {'id': 2, 'mediaId': 22, 'progress': 0},
                ],
              },
            ],
          },
        },
      });

      final result = await service.getUserMangaList(1, token);

      expect(result.keys, containsAll(['CURRENT', 'custom:Must Reread']));
      expect(result['custom:Must Reread'], [
        {'id': 2, 'mediaId': 22, 'progress': 0},
      ]);
    });

    test('throws an Exception on a non-200 response', () async {
      final service = serviceReturning({}, status: 500);

      await expectLater(
        () => service.getUserMangaList(1, token),
        throwsA(isA<Exception>()),
      );
    });

    test('throws an Exception and increments authExpiredNotifier on 401',
        () async {
      final service = serviceReturning({}, status: 401);

      await expectLater(
        () => service.getUserMangaList(1, token),
        throwsA(isA<Exception>()),
      );
      expect(authExpiredNotifier.value, 1);
    });

    test('throws an Exception when the lists field is missing', () async {
      final service = serviceReturning({
        'data': {'MediaListCollection': {}},
      });

      await expectLater(
        () => service.getUserMangaList(1, token),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('getActivityFeed', () {
    test('sends isFollowing and page variables, and omits userId when absent',
        () async {
      final service = serviceReturning({
        'data': {
          'Page': {
            'pageInfo': {'hasNextPage': false},
            'activities': <dynamic>[],
          },
        },
      });

      await service.getActivityFeed(token, isFollowing: false, page: 2);

      expect(log.single.variables['isFollowing'], false);
      expect(log.single.variables['page'], 2);
      expect(log.single.variables.containsKey('userId'), isFalse);
    });

    test('includes the userId variable when passed', () async {
      final service = serviceReturning({
        'data': {
          'Page': {
            'pageInfo': {'hasNextPage': false},
            'activities': <dynamic>[],
          },
        },
      });

      await service.getActivityFeed(token, userId: 99);

      expect(log.single.variables['userId'], 99);
    });

    test('returns hasNextPage and activities from the response', () async {
      final service = serviceReturning({
        'data': {
          'Page': {
            'pageInfo': {'hasNextPage': true},
            'activities': [
              {'id': 1, 'type': 'TEXT'},
            ],
          },
        },
      });

      final result = await service.getActivityFeed(token);

      expect(result.hasNextPage, isTrue);
      expect(result.activities, [
        {'id': 1, 'type': 'TEXT'},
      ]);
    });

    test(
        'returns empty activities and increments authExpiredNotifier on 401',
        () async {
      final service = serviceReturning({}, status: 401);

      final result = await service.getActivityFeed(token);

      expect(result.activities, isEmpty);
      expect(result.hasNextPage, isFalse);
      expect(authExpiredNotifier.value, 1);
    });
  });

  group('getAnimeDetail', () {
    test('returns the Media map on a successful response', () async {
      final service = serviceReturning({
        'data': {
          'Media': {'id': 5, 'title': {'romaji': 'Title'}},
        },
      });

      final result = await service.getAnimeDetail(5);

      expect(result, {
        'id': 5,
        'title': {'romaji': 'Title'},
      });
    });

    test('returns null on a non-200 response', () async {
      final service = serviceReturning({}, status: 404);

      final result = await service.getAnimeDetail(5);

      expect(result, isNull);
    });
  });

  group('429 rate-limit retry', () {
    test(
        'retries once after a 429 with retry-after, returns the retried '
        'response, and resets rateLimitActiveNotifier', () async {
      final rateLimitEvents = <bool>[];
      void onRateLimitChange() =>
          rateLimitEvents.add(rateLimitActiveNotifier.value);
      rateLimitActiveNotifier.addListener(onRateLimitChange);
      addTearDown(() => rateLimitActiveNotifier.removeListener(onRateLimitChange));

      final service = AniListService(
        client: mockAniList(log, (_) {
          if (log.length == 1) {
            return jsonResponse({}, status: 429, headers: {'retry-after': '0'});
          }
          return jsonResponse({
            'data': {
              'Media': {'id': 7},
            },
          });
        }),
      );

      final result = await service.getAnimeDetail(7);

      expect(log.length, 2);
      expect(result, {'id': 7});
      expect(rateLimitEvents, contains(true));
      expect(rateLimitActiveNotifier.value, isFalse);
    });
  });

  group('getUserFollowCounts', () {
    test('parses followersPage and followingPage pageInfo totals', () async {
      final service = serviceReturning({
        'data': {
          'followersPage': {
            'pageInfo': {'total': 12},
          },
          'followingPage': {
            'pageInfo': {'total': 34},
          },
        },
      });

      final result = await service.getUserFollowCounts(1, token);

      expect(result, {'followers': 12, 'following': 34});
    });

    test('returns zeros on a non-200 response', () async {
      final service = serviceReturning({}, status: 500);

      final result = await service.getUserFollowCounts(1, token);

      expect(result, {'followers': 0, 'following': 0});
    });
  });

  group('getPublicUserList', () {
    test('skips custom lists', () async {
      final service = serviceReturning({
        'data': {
          'MediaListCollection': {
            'lists': [
              {
                'status': 'CURRENT',
                'isCustomList': false,
                'entries': [
                  {'progress': 1},
                ],
              },
              {
                'status': null,
                'isCustomList': true,
                'entries': [
                  {'progress': 2},
                ],
              },
            ],
          },
        },
      });

      final result = await service.getPublicUserList(1, 'ANIME');

      expect(result.keys, ['CURRENT']);
    });

    test('sends no Authorization header', () async {
      final service = serviceReturning({
        'data': {
          'MediaListCollection': {'lists': <dynamic>[]},
        },
      });

      await service.getPublicUserList(1, 'ANIME');

      expect(log.single.authorization, isNull);
    });
  });

  group('getUserActivityDays', () {
    test('stops paging when an activity is older than 365 days', () async {
      final now = DateTime.now();
      final recentTs =
          now.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
      final oldTs =
          now.subtract(const Duration(days: 400)).millisecondsSinceEpoch ~/
              1000;
      final recentKey =
          _dateKey(DateTime.fromMillisecondsSinceEpoch(recentTs * 1000));

      final service = AniListService(
        client: mockAniList(log, (_) {
          return jsonResponse({
            'data': {
              'Page': {
                'activities': [
                  {'createdAt': recentTs},
                  {'createdAt': oldTs},
                  // Would also be recent, but must never be reached: the
                  // loop should stop as soon as the older activity above is
                  // seen.
                  {'createdAt': recentTs},
                ],
              },
            },
          });
        }),
      );

      final result = await service.getUserActivityDays(1, token);

      expect(log, hasLength(1));
      expect(result, {recentKey: 1});
    });

    test('aggregates activity counts per day across pages', () async {
      final now = DateTime.now();
      final sameInstant =
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000;
      final otherDayTs =
          now.subtract(const Duration(days: 40)).millisecondsSinceEpoch ~/
              1000;
      final sameInstantKey =
          _dateKey(DateTime.fromMillisecondsSinceEpoch(sameInstant * 1000));
      final otherDayKey =
          _dateKey(DateTime.fromMillisecondsSinceEpoch(otherDayTs * 1000));

      final service = AniListService(
        client: mockAniList(log, (req) {
          final page = req.variables['page'];
          if (page == 1) {
            return jsonResponse({
              'data': {
                'Page': {
                  'activities': [
                    {'createdAt': sameInstant},
                    {'createdAt': sameInstant},
                    {'createdAt': otherDayTs},
                  ],
                },
              },
            });
          }
          return jsonResponse({
            'data': {
              'Page': {'activities': <dynamic>[]},
            },
          });
        }),
      );

      final result = await service.getUserActivityDays(1, token);

      expect(log, hasLength(2));
      expect(result[sameInstantKey], 2);
      expect(result[otherDayKey], 1);
    });
  });
}
