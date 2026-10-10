import 'package:anispark/services/affinity_api.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/mock_anilist.dart';

const _viewerId = 1;
const _otherId = 7;

/// A MediaListCollection response with [lists] of entry maps.
Map<String, dynamic> _collection(List<List<Object?>> lists) => {
      'data': {
        'MediaListCollection': {
          'lists': [
            for (final entries in lists) {'entries': entries},
          ],
        },
      },
    };

Map<String, dynamic> _row(int mediaId, Object? score, {String status = 'COMPLETED', String? title}) => {
      'mediaId': mediaId,
      'status': status,
      'score': score,
      if (title != null)
        'media': {
          'title': {'romaji': '$title (romaji)', 'english': title, 'native': null},
          'coverImage': {'medium': 'https://img/$mediaId.jpg'},
        },
    };

final _privateUser = jsonResponse({
  'errors': [
    {'message': 'Private User', 'status': 404},
  ],
  'data': {'MediaListCollection': null},
}, status: 404);

void main() {
  late List<RecordedRequest> log;
  var now = DateTime(2026, 10, 10, 12);

  setUp(() {
    log = [];
    now = DateTime(2026, 10, 10, 12);
    authExpiredNotifier.value = 0;
    AffinityApi.clearViewerMemo();
  });

  AffinityApi apiAnswering(http.Response Function(RecordedRequest request) handler) => AffinityApi(
        service: AniListService(client: mockAniList(log, handler)),
        clock: () => now,
      );

  AffinityApi apiReturning(Object body, {int status = 200}) =>
      apiAnswering((_) => jsonResponse(body, status: status));

  group('fetchEntries', () {
    test('asks for the non-planning entries with 0–100 scores and nothing else', () async {
      final api = apiReturning(_collection([]));

      await api.fetchEntries(_otherId, 'ANIME', token: 'tok');

      final request = log.single;
      expect(request.variables, {'userId': _otherId, 'type': 'ANIME'});
      expect(request.query, contains('MediaListCollection(userId: \$userId, type: \$type, status_not: PLANNING)'));
      expect(request.query, contains('mediaId status score(format: POINT_100)'));
      expect(request.query, isNot(contains('media {')), reason: 'titles come from the viewer\'s list');
      expect(request.authorization, 'Bearer tok');
    });

    test('also asks for titles and covers when needed', () async {
      final api = apiReturning(_collection([]));

      await api.fetchEntries(_viewerId, 'MANGA', withMedia: true);

      final request = log.single;
      expect(request.variables, {'userId': _viewerId, 'type': 'MANGA'});
      expect(request.query, contains('media { title { romaji english native } coverImage { medium } }'));
      expect(request.authorization, isNull);
    });

    test('parses every list, counting entries repeated in custom lists once', () async {
      final api = apiReturning(_collection([
        [_row(1, 80, title: 'Bebop'), _row(2, 0, status: 'CURRENT')],
        [_row(1, 80, title: 'Bebop')],
      ]));

      final entries = await api.fetchEntries(_viewerId, 'ANIME', withMedia: true);

      expect(entries.map((e) => e.mediaId), [1, 2]);
      final bebop = entries.first;
      expect(bebop.score, 80);
      expect(bebop.status, 'COMPLETED');
      expect(bebop.title, {'romaji': 'Bebop (romaji)', 'english': 'Bebop'});
      expect(bebop.coverUrl, 'https://img/1.jpg');
      expect(entries.last.status, 'CURRENT');
      expect(entries.last.isScored, isFalse);
    });

    test('parses defensively: skips rows without a media id, clamps odd scores', () async {
      final api = apiReturning({
        'data': {
          'MediaListCollection': {
            'lists': [
              {
                'entries': [
                  _row(1, 72.5),
                  _row(2, 'ninety'),
                  _row(3, 140),
                  _row(4, -5),
                  _row(5, null),
                  {'mediaId': 'six', 'score': 50},
                  'junk',
                  null,
                ],
              },
              {'entries': null},
              'junk',
            ],
          },
        },
      });

      final entries = await api.fetchEntries(_otherId, 'ANIME');

      expect(entries.map((e) => (e.mediaId, e.score)), [(1, 72.5), (2, 0), (3, 100), (4, 0), (5, 0)]);
    });

    test('returns nothing for an empty collection', () async {
      final api = apiReturning({
        'data': {
          'MediaListCollection': {'lists': null},
        },
      });

      expect(await api.fetchEntries(_otherId, 'ANIME'), isEmpty);
    });

    test('reports a private list (AniList answers 404) as unavailable', () async {
      final api = apiAnswering((_) => _privateUser);

      await expectLater(api.fetchEntries(_otherId, 'ANIME'), throwsA(isA<AffinityUnavailableException>()));
    });

    test('reports a missing collection as unavailable', () async {
      final api = apiReturning({
        'data': {'MediaListCollection': null},
      });

      await expectLater(api.fetchEntries(_otherId, 'ANIME'), throwsA(isA<AffinityUnavailableException>()));
    });

    test('lets other failures through', () async {
      final api = apiReturning({'errors': []}, status: 500);

      await expectLater(
        api.fetchEntries(_otherId, 'ANIME'),
        throwsA(isA<AniListRequestException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('rejects an unknown media type without sending anything', () async {
      final api = apiReturning(_collection([]));

      await expectLater(api.fetchEntries(_otherId, 'NOVEL'), throwsArgumentError);
      expect(log, isEmpty);
    });
  });

  group('fetchShared', () {
    /// Answers the viewer's and the other users' requests from [lists].
    AffinityApi apiWithLists(Map<int, Object> lists) => apiAnswering((request) {
          final body = lists[request.variables['userId']];
          return body is http.Response ? body : jsonResponse(body ?? _collection([]));
        });

    test('compares the viewer\'s list (with titles) to the other user\'s', () async {
      final api = apiWithLists({
        _viewerId: _collection([
          [_row(1, 90, title: 'Bebop'), _row(2, 60, title: 'Trigun'), _row(3, 70, title: 'Monster')],
        ]),
        _otherId: _collection([
          [_row(3, 40, status: 'DROPPED'), _row(1, 80), _row(9, 100)],
        ]),
      });

      final shared = await api.fetchShared(viewerId: _viewerId, otherId: _otherId, type: 'ANIME', token: 'tok');

      expect(shared.map((t) => (t.mediaId, t.myScore, t.theirScore)), [(1, 90.0, 80.0), (3, 70.0, 40.0)]);
      expect(shared.first.title?['english'], 'Bebop');
      expect(shared.last.theirStatus, 'DROPPED');
      expect(log.map((r) => r.variables['userId']), [_viewerId, _otherId]);
      expect(log.first.query, contains('media {'));
      expect(log.last.query, isNot(contains('media {')));
      expect(log.map((r) => r.authorization), everyElement('Bearer tok'));
    });

    test('skips the other user\'s list when the viewer has nothing of that type', () async {
      final api = apiWithLists({_viewerId: _collection([])});

      final shared = await api.fetchShared(viewerId: _viewerId, otherId: _otherId, type: 'MANGA', token: 'tok');

      expect(shared, isEmpty);
      expect(log, hasLength(1));
    });

    test('reports the other user\'s private list as unavailable', () async {
      final api = apiWithLists({
        _viewerId: _collection([
          [_row(1, 90, title: 'Bebop')],
        ]),
        _otherId: _privateUser,
      });

      await expectLater(
        api.fetchShared(viewerId: _viewerId, otherId: _otherId, type: 'ANIME', token: 'tok'),
        throwsA(isA<AffinityUnavailableException>()),
      );
    });

    group('reuses the viewer\'s own list', () {
      final viewerList = _collection([
        [_row(1, 90, title: 'Bebop')],
      ]);

      int viewerRequests() => log.where((r) => r.variables['userId'] == _viewerId).length;

      test('across profiles for a few minutes', () async {
        final api = apiWithLists({_viewerId: viewerList});

        await api.fetchShared(viewerId: _viewerId, otherId: 7, type: 'ANIME', token: 'tok');
        now = now.add(AffinityApi.viewerListTtl - const Duration(seconds: 1));
        await api.fetchShared(viewerId: _viewerId, otherId: 8, type: 'ANIME', token: 'tok');

        expect(viewerRequests(), 1);
        expect(log.map((r) => r.variables['userId']), [_viewerId, 7, 8]);
      });

      test('but not after it expires', () async {
        final api = apiWithLists({_viewerId: viewerList});

        await api.fetchShared(viewerId: _viewerId, otherId: 7, type: 'ANIME', token: 'tok');
        now = now.add(AffinityApi.viewerListTtl);
        await api.fetchShared(viewerId: _viewerId, otherId: 8, type: 'ANIME', token: 'tok');

        expect(viewerRequests(), 2);
      });

      test('but not for another media type or session', () async {
        final api = apiWithLists({_viewerId: viewerList});

        await api.fetchShared(viewerId: _viewerId, otherId: 7, type: 'ANIME', token: 'tok');
        await api.fetchShared(viewerId: _viewerId, otherId: 7, type: 'MANGA', token: 'tok');
        await api.fetchShared(viewerId: _viewerId, otherId: 7, type: 'ANIME', token: 'new-session');

        expect(viewerRequests(), 3);
      });

      test('but not after it failed to load', () async {
        var failViewer = true;
        final api = apiAnswering((request) {
          if (request.variables['userId'] == _viewerId) {
            return failViewer ? jsonResponse({'errors': []}, status: 500) : jsonResponse(viewerList);
          }
          return jsonResponse(_collection([]));
        });

        await expectLater(
          api.fetchShared(viewerId: _viewerId, otherId: 7, type: 'ANIME', token: 'tok'),
          throwsA(isA<AniListRequestException>()),
        );
        failViewer = false;
        await api.fetchShared(viewerId: _viewerId, otherId: 7, type: 'ANIME', token: 'tok');

        expect(viewerRequests(), 2);
      });
    });
  });
}
