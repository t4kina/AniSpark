import 'package:anispark/screens/profile_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';

/// Logged in with a fresh cached profile (nothing is fetched) whose
/// statistics come as AniList sends them: scores on 0–100.
class _StatsAuth extends FakeAuthService {
  _StatsAuth({required String scoreFormat, required List<Map<String, dynamic>> animeScores, List<dynamic>? mangaGenres})
      : super(fakeToken: 'token', fakeUser: {
          'id': 7,
          'name': 'Faye',
          'mediaListOptions': {'scoreFormat': scoreFormat},
          'statistics': {
            'anime': {
              'count': 3,
              'scores': animeScores,
              'genres': [
                {'genre': 'Drama', 'count': 5, 'meanScore': 70.0},
                {'genre': 'Action', 'count': 2, 'meanScore': 85.0},
              ],
              'releaseYears': [
                {'releaseYear': 2021, 'count': 4},
                {'releaseYear': 1998, 'count': 1},
              ],
            },
            'manga': {'count': 0, 'genres': mangaGenres ?? const []},
          },
        });

  @override
  Map<String, dynamic>? get profileExtras => {
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'favoriteAnime': const [],
        'favoriteCharacters': const [],
        'followersCount': 0,
        'followingCount': 0,
        'activityDays': const <String, dynamic>{},
        'following': const [],
      };
}

Future<void> _pumpProfile(WidgetTester tester, _StatsAuth auth) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(appWith(const ProfileScreen(), cache: ApiCache(MemoryCacheStore()), auth: auth));
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('score bars are labelled once each, in the user\'s score format', (tester) async {
    await _pumpProfile(
      tester,
      _StatsAuth(scoreFormat: 'POINT_10_DECIMAL', animeScores: [
        for (final score in [60, 65, 70, 75, 100]) {'score': score, 'count': 2},
      ]),
    );
    await _expand(tester, 'SCORE DISTRIBUTION');

    expect(tester.takeException(), isNull);
    for (final label in ['6.0', '6.5', '7.0', '7.5', '10.0']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('a 100-point user reads 100-point labels', (tester) async {
    await _pumpProfile(
      tester,
      _StatsAuth(scoreFormat: 'POINT_100', animeScores: [
        {'score': 65, 'count': 1},
        {'score': 90, 'count': 3},
      ]),
    );
    await _expand(tester, 'SCORE DISTRIBUTION');

    expect(find.text('65'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
  });

  testWidgets('many different scores are grouped by whole point', (tester) async {
    await _pumpProfile(
      tester,
      _StatsAuth(scoreFormat: 'POINT_10_DECIMAL', animeScores: [
        for (var score = 61; score <= 80; score++) {'score': score, 'count': 1},
      ]),
    );
    await _expand(tester, 'SCORE DISTRIBUTION');

    expect(find.text('7.0'), findsOneWidget, reason: '61–70');
    expect(find.text('8.0'), findsOneWidget, reason: '71–80');
    expect(find.text('6.1'), findsNothing);
  });

  testWidgets('genre means use the score format and a missing list says so', (tester) async {
    await _pumpProfile(
      tester,
      _StatsAuth(scoreFormat: 'POINT_10_DECIMAL', animeScores: const []),
    );
    await _expand(tester, 'ANIME GENRES');

    expect(find.text('5 anime  ·  7.0 ★'), findsOneWidget);
    expect(find.text('2 anime  ·  8.5 ★'), findsOneWidget);
    expect(find.text('No data'), findsOneWidget, reason: 'the manga genres card, with no manga');
  });

  testWidgets('the activity graph opens on the latest weeks', (tester) async {
    await _pumpProfile(
      tester,
      _StatsAuth(scoreFormat: 'POINT_10_DECIMAL', animeScores: const []),
    );

    final heatmap = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_HeatmapPainter');
    final rect = tester.getRect(heatmap);
    final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(rect.width, greaterThan(screenWidth), reason: 'a year is wider than the screen');
    expect(rect.right, lessThanOrEqualTo(screenWidth), reason: 'today is visible without scrolling');
  });

  testWidgets('eras are listed oldest first with their counts', (tester) async {
    await _pumpProfile(
      tester,
      _StatsAuth(scoreFormat: 'POINT_10_DECIMAL', animeScores: const []),
    );
    await _expand(tester, 'TITLES BY ERA');

    final early = tester.getTopLeft(find.text('1995–1999'));
    final late = tester.getTopLeft(find.text('2020–2024'));
    expect(early.dy, lessThan(late.dy));
    expect(find.text('4'), findsOneWidget);
  });
}
