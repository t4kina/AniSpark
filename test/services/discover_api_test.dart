import 'dart:convert';

import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/discover_api.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/mock_anilist.dart';

Map<String, dynamic> _schedule(int id, {int airingAt = 1000, bool isAdult = false}) => {
      'id': id,
      'airingAt': airingAt,
      'episode': 1,
      'media': {'id': id, 'isAdult': isAdult, 'title': {'romaji': 'Show $id'}},
    };

Map<String, dynamic> _schedulePage(List<Object?> schedules, {bool hasNextPage = false}) => {
      'data': {
        'Page': {
          'pageInfo': {'hasNextPage': hasNextPage},
          'airingSchedules': schedules,
        },
      },
    };

void main() {
  late List<RecordedRequest> log;

  setUp(() {
    log = [];
    authExpiredNotifier.value = 0;
    rateLimitActiveNotifier.value = false;
  });

  DiscoverApi apiAnswering(http.Response Function(RecordedRequest request) handler) =>
      DiscoverApi(service: AniListService(client: mockAniList(log, handler)));

  DiscoverApi apiReturning(Object body, {int status = 200}) =>
      apiAnswering((_) => jsonResponse(body, status: status));

  group('airingSchedule', () {
    final from = DateTime.utc(2026, 10, 10);
    final to = DateTime.utc(2026, 10, 17);
    final fromSeconds = from.millisecondsSinceEpoch ~/ 1000;
    final toSeconds = to.millisecondsSinceEpoch ~/ 1000;

    test('sends the time window in epoch seconds without a token', () async {
      final api = apiReturning(_schedulePage([]));

      await api.airingSchedule(from: from, to: to);

      expect(log.single.variables, {
        'page': 1,
        'perPage': DiscoverApi.schedulePageSize,
        'from': fromSeconds - 1, // airingAt_greater is exclusive
        'to': toSeconds,
        'withListStatus': false,
      });
      expect(log.single.authorization, isNull);
      expect(log.single.query, contains('airingSchedules(airingAt_greater: \$from'));
    });

    test('asks for list statuses and sends the token when logged in', () async {
      final api = apiReturning(_schedulePage([]));

      await api.airingSchedule(from: from, to: to, token: 'tok');

      expect(log.single.variables['withListStatus'], isTrue);
      expect(log.single.authorization, 'Bearer tok');
      expect(log.single.query, contains('mediaListEntry @include(if: \$withListStatus)'));
    });

    test('fetches pages until hasNextPage is false and keeps their order', () async {
      final api = apiAnswering((request) => switch (request.variables['page']) {
            1 => jsonResponse(_schedulePage([_schedule(1), _schedule(2)], hasNextPage: true)),
            2 => jsonResponse(_schedulePage([_schedule(3)], hasNextPage: true)),
            _ => jsonResponse(_schedulePage([_schedule(4)])),
          });

      final episodes = await api.airingSchedule(from: from, to: to);

      expect(log.map((r) => r.variables['page']), [1, 2, 3]);
      expect(episodes.map((e) => e['id']), [1, 2, 3, 4]);
    });

    test('stops at an empty page even if AniList reports more', () async {
      final api = apiReturning(_schedulePage([], hasNextPage: true));

      await api.airingSchedule(from: from, to: to);

      expect(log, hasLength(1));
    });

    test('never fetches more than maxSchedulePages pages', () async {
      final api = apiReturning(_schedulePage([_schedule(1)], hasNextPage: true));

      final episodes = await api.airingSchedule(from: from, to: to);

      expect(log, hasLength(DiscoverApi.maxSchedulePages));
      expect(episodes, hasLength(DiscoverApi.maxSchedulePages));
    });

    test('leaves out adult titles and entries without media', () async {
      final api = apiReturning(_schedulePage([
        _schedule(1),
        _schedule(2, isAdult: true),
        {'id': 3, 'airingAt': 1000, 'episode': 1, 'media': null},
        'not a map',
      ]));

      final episodes = await api.airingSchedule(from: from, to: to);

      expect(episodes.map((e) => e['id']), [1]);
    });

    test('throws on an unexpected response shape', () async {
      final api = apiReturning({
        'data': {'Page': null},
      });

      await expectLater(api.airingSchedule(from: from, to: to), throwsFormatException);
    });

    test('throws AniListRequestException on HTTP errors', () async {
      final api = apiReturning({'errors': []}, status: 500);

      await expectLater(
        api.airingSchedule(from: from, to: to),
        throwsA(isA<AniListRequestException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });

  group('weekSchedule', () {
    final now = DateTime(2026, 10, 10, 15, 30);

    test('asks for today from midnight through the next seven days', () async {
      final api = apiReturning(_schedulePage([]));

      await api.weekSchedule(token: 't', now: now);

      final midnight = DateTime(2026, 10, 10).millisecondsSinceEpoch ~/ 1000;
      final end = DateTime(2026, 10, 17).millisecondsSinceEpoch ~/ 1000;
      expect(log.single.variables['from'], midnight - 1);
      expect(log.single.variables['to'], end);
      expect(log.single.variables['withListStatus'], isTrue);
      expect(log.single.authorization, 'Bearer t');
    });

    test('works logged out, without list statuses', () async {
      final api = apiReturning(_schedulePage([]));

      await api.weekSchedule(now: now);

      expect(log.single.variables['withListStatus'], isFalse);
      expect(log.single.authorization, isNull);
    });

    test('names the cache after the local day', () {
      expect(DiscoverApi.weekCacheName(DateTime(2026, 3, 5, 23, 59)), 'calendar:2026-03-05');
    });
  });

  group('currentlyWatching', () {
    final now = DateTime(2026, 10, 10, 15);
    int at(Duration offset) => now.add(offset).millisecondsSinceEpoch ~/ 1000;

    Map<String, dynamic> entry(int id, String? status, int airingAt) => {
          'id': id,
          'airingAt': airingAt,
          'media': {'id': id, 'mediaListEntry': status == null ? null : {'status': status}},
        };

    test('keeps CURRENT titles that have not aired yet and air within seven days', () {
      final week = [
        entry(1, 'CURRENT', at(const Duration(hours: 2))),
        entry(2, 'PLANNING', at(const Duration(hours: 2))),
        entry(3, null, at(const Duration(hours: 2))),
        entry(4, 'CURRENT', at(const Duration(hours: -2))),
        entry(5, 'CURRENT', at(const Duration(days: 7, hours: 1))),
        entry(6, 'CURRENT', at(const Duration(days: 6))),
      ];

      final kept = DiscoverApi.currentlyWatching(week, now: now);

      expect([for (final s in kept) s['id']], [1, 6]);
    });

    test('ignores entries without an airing time', () {
      expect(DiscoverApi.currentlyWatching([entry(1, 'CURRENT', 0)], now: now), isEmpty);
    });
  });

  group('seasonMedia', () {
    Map<String, dynamic> seasonPage(List<Object?> media, {Object? pageInfo}) => {
          'data': {
            'Page': {'pageInfo': pageInfo, 'media': media},
          },
        };

    test('sends the season, sort with an id tiebreaker and page', () async {
      final api = apiReturning(seasonPage([], pageInfo: {'hasNextPage': false}));

      await api.seasonMedia(season: 'FALL', year: 2026, sort: 'SCORE_DESC', page: 3);

      expect(log.single.variables, {
        'page': 3,
        'perPage': DiscoverApi.seasonPageSize,
        'season': 'FALL',
        'seasonYear': 2026,
        'sort': ['SCORE_DESC', 'ID'],
      });
      expect(log.single.authorization, isNull);
    });

    test('omits the format filter when empty (format_in: null is a 500)', () async {
      final api = apiReturning(seasonPage([]));

      await api.seasonMedia(season: 'WINTER', year: 2027, sort: 'POPULARITY_DESC');

      expect(log.single.variables.containsKey('formats'), isFalse);
    });

    test('sends the formats sorted', () async {
      final api = apiReturning(seasonPage([]));

      await api.seasonMedia(
        season: 'SPRING',
        year: 2025,
        sort: 'TRENDING_DESC',
        formats: {'OVA', 'MOVIE', 'ONA'},
      );

      expect(log.single.variables['formats'], ['MOVIE', 'ONA', 'OVA']);
    });

    test('parses media and hasNextPage', () async {
      final api = apiReturning(seasonPage(
        [
          {'id': 1, 'title': {'romaji': 'A'}, 'averageScore': 80},
          {'id': 2, 'title': {'romaji': 'B'}},
        ],
        pageInfo: {'hasNextPage': true},
      ));

      final page = await api.seasonMedia(season: 'FALL', year: 2026, sort: 'POPULARITY_DESC');

      expect(page.media.map((m) => m['id']), [1, 2]);
      expect(page.hasNextPage, isTrue);
    });

    test('treats a missing pageInfo as the last page', () async {
      final api = apiReturning(seasonPage([{'id': 1}]));

      final page = await api.seasonMedia(season: 'FALL', year: 2026, sort: 'POPULARITY_DESC');

      expect(page.hasNextPage, isFalse);
    });

    test('throws on an unexpected response shape', () async {
      final api = apiReturning({
        'data': {
          'Page': {'media': 'oops'},
        },
      });

      await expectLater(
        api.seasonMedia(season: 'FALL', year: 2026, sort: 'POPULARITY_DESC'),
        throwsFormatException,
      );
    });
  });

  group('SeasonPage', () {
    test('survives a JSON round trip, as stored by ApiCache', () {
      const page = SeasonPage(
        media: [
          {'id': 1, 'title': {'romaji': 'A'}},
        ],
        hasNextPage: true,
      );

      final restored = SeasonPage.fromJson(jsonDecode(jsonEncode(page)));

      expect(restored.media, page.media);
      expect(restored.hasNextPage, isTrue);
    });

    test('rejects data of another shape', () {
      expect(() => SeasonPage.fromJson([1, 2]), throwsA(isA<TypeError>()));
    });
  });
}
