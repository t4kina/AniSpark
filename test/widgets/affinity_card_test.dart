import 'package:anispark/screens/compare_screen.dart';
import 'package:anispark/services/affinity_api.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/utils/affinity.dart';
import 'package:anispark/widgets/profile/affinity_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';

const _viewerId = 1;
const _otherId = 7;

Map<String, dynamic> _collection(List<Map<String, Object?>> entries) => {
      'data': {
        'MediaListCollection': {
          'lists': [
            {'entries': entries},
          ],
        },
      },
    };

/// [count] titles scored 8, 16, 24…, with titles when [withMedia].
List<Map<String, Object?>> _rows(int count, {bool withMedia = false, bool reversed = false}) => [
      for (var i = 1; i <= count; i++)
        {
          'mediaId': i,
          'status': 'COMPLETED',
          'score': (reversed ? count + 1 - i : i) * 8,
          if (withMedia)
            'media': {
              'title': {'english': 'Show $i'},
              'coverImage': {'medium': null},
            },
        },
    ];

final _viewerAnime = _collection(_rows(12, withMedia: true));
final _sameScores = _collection(_rows(12));

void main() {
  late ApiCache cache;
  late List<RecordedRequest> log;

  setUp(() {
    cache = ApiCache(MemoryCacheStore());
    log = [];
    AffinityApi.clearViewerMemo();
  });

  /// Answers manga with empty lists, the viewer's anime with [_viewerAnime]
  /// and the other user's anime with [other].
  AffinityApi apiWith(http.Response Function() other) => AffinityApi(
        service: AniListService(
          client: mockAniList(log, (request) {
            if (request.variables['type'] == 'MANGA') return jsonResponse(_collection([]));
            if (request.variables['userId'] == _viewerId) return jsonResponse(_viewerAnime);
            return other();
          }),
        ),
      );

  AuthService loggedIn() => FakeAuthService(fakeToken: 'tok', fakeUser: {'id': _viewerId, 'name': 'spike'});

  Future<void> pumpCard(
    WidgetTester tester, {
    required AffinityApi api,
    AuthService? auth,
    int userId = _otherId,
  }) async {
    await tester.pumpWidget(appWith(
      Scaffold(
        body: ListView(children: [AffinityCard(userId: userId, userName: 'faye', api: api)]),
      ),
      cache: cache,
      auth: auth,
    ));
    // Loading starts after the first frame, then the answers arrive.
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('stays hidden and sends nothing when logged out', (tester) async {
    await pumpCard(tester, api: apiWith(() => jsonResponse(_sameScores)));

    expect(find.descendant(of: find.byType(AffinityCard), matching: find.byType(Text)), findsNothing);
    expect(log, isEmpty);
  });

  testWidgets('stays hidden and sends nothing on the viewer\'s own profile', (tester) async {
    await pumpCard(tester, api: apiWith(() => jsonResponse(_sameScores)), auth: loggedIn(), userId: _viewerId);

    expect(find.descendant(of: find.byType(AffinityCard), matching: find.byType(Text)), findsNothing);
    expect(log, isEmpty);
  });

  testWidgets('shows the affinity once enough titles are scored by both', (tester) async {
    await pumpCard(tester, api: apiWith(() => jsonResponse(_sameScores)), auth: loggedIn());

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);
    expect(find.text('Manga'), findsNothing, reason: 'no manga in common, so no manga row');
    expect(
      log.map((r) => (r.variables['userId'], r.variables['type'])),
      unorderedEquals([(_viewerId, 'ANIME'), (_otherId, 'ANIME'), (_viewerId, 'MANGA')]),
      reason: 'the other user\'s manga is skipped when the viewer has none',
    );
  });

  testWidgets('shows a negative affinity for opposite tastes', (tester) async {
    await pumpCard(tester, api: apiWith(() => jsonResponse(_collection(_rows(12, reversed: true)))), auth: loggedIn());

    expect(find.text('-100%'), findsOneWidget);
  });

  testWidgets('shows no percentage when too few titles are scored by both', (tester) async {
    await pumpCard(tester, api: apiWith(() => jsonResponse(_collection(_rows(minScoredInCommon - 1)))), auth: loggedIn());

    expect(find.text('Anime'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('–'), findsOneWidget);
  });

  testWidgets('shows a private state instead of crashing when the list is private', (tester) async {
    await pumpCard(
      tester,
      api: apiWith(() => jsonResponse({
            'errors': [
              {'message': 'Private User', 'status': 404},
            ],
            'data': {'MediaListCollection': null},
          }, status: 404)),
      auth: loggedIn(),
    );

    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('Anime'), findsNothing);
  });

  testWidgets('fails quietly into a retry that recovers', (tester) async {
    var fail = true;
    await pumpCard(
      tester,
      api: apiWith(() => fail ? jsonResponse({'errors': []}, status: 500) : jsonResponse(_sameScores)),
      auth: loggedIn(),
    );

    expect(find.byTooltip('Retry'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);

    fail = false;
    await tester.tap(find.byTooltip('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('100%'), findsOneWidget);
    expect(find.byTooltip('Retry'), findsNothing);
  });

  testWidgets('shows a recently cached comparison without sending anything', (tester) async {
    final shared = sharedTitles(
      [for (var i = 1; i <= 12; i++) AffinityEntry(mediaId: i, score: i * 8.0, title: {'english': 'Show $i'})],
      [for (var i = 1; i <= 12; i++) AffinityEntry(mediaId: i, score: i * 8.0)],
    );
    await cache.write(ApiCache.userKey(_viewerId, 'affinity:$_otherId:ANIME'), shared);
    await cache.write(ApiCache.userKey(_viewerId, 'affinity:$_otherId:MANGA'), <SharedTitle>[]);

    await pumpCard(tester, api: apiWith(() => jsonResponse(_sameScores)), auth: loggedIn());

    expect(find.text('100%'), findsOneWidget);
    expect(log, isEmpty);
  });

  testWidgets('caches the comparison per viewer', (tester) async {
    await pumpCard(tester, api: apiWith(() => jsonResponse(_sameScores)), auth: loggedIn());

    final cached = await cache.read(ApiCache.userKey(_viewerId, 'affinity:$_otherId:ANIME'));
    expect(SharedTitle.listFromJson(cached?.value), hasLength(12));
  });

  testWidgets('opens the comparison from the row', (tester) async {
    await pumpCard(tester, api: apiWith(() => jsonResponse(_sameScores)), auth: loggedIn());

    await tester.tap(find.text('Anime'));
    await tester.pumpAndSettle();

    expect(find.byType(CompareScreen), findsOneWidget);
    expect(find.text('Show 12'), findsOneWidget);
  });
}
