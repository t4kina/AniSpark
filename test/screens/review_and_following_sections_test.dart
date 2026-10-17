import 'dart:io';

import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/screens/review_screen.dart';
import 'package:anispark/screens/reviews_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/services/media_extras_api.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/detail/following_section.dart';
import 'package:anispark/widgets/detail/review_card.dart';
import 'package:anispark/widgets/detail/reviews_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

/// A logged-in session without touching secure storage.
class _LoggedInAuth extends AuthService {
  @override
  String? get token => 'test-token';

  @override
  Map<String, dynamic>? get user => {'id': 7};

  @override
  bool get isLoggedIn => true;
}

const _review = Review(
  id: 5,
  user: MiniUser(id: 9, name: 'Ann'),
  summary: 'Loved every minute',
  rating: 367,
  ratingAmount: 781,
  score: 86,
);

FollowingEntry _entry(int id, String status, {int progress = 0, double score = 0}) =>
    FollowingEntry(user: MiniUser(id: id, name: 'Friend $id'), status: status, progress: progress, score: score);

void main() {
  final offline = OfflineHttpOverrides();
  late ApiCache cache;

  setUpAll(() => HttpOverrides.global = offline);

  setUp(() {
    offline.requests = 0;
    cache = ApiCache(MemoryCacheStore());
  });

  Widget app(Widget child, {AuthService? auth, bool scroll = true}) => MultiProvider(
        providers: [
          Provider.value(value: cache),
          ChangeNotifierProvider<AuthService>(create: (_) => auth ?? AuthService()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(home: scroll ? Scaffold(body: SingleChildScrollView(child: child)) : child),
      );

  group('ReviewsSection', () {
    testWidgets('stays hidden when there are no reviews to show', (tester) async {
      await tester.pumpWidget(app(const ReviewsSection(mediaId: 1)));
      await tester.pump();

      expect(find.byType(ReviewCard), findsNothing);
      expect(find.text('See all'), findsNothing);
      expect(offline.requests, 1);
    });

    testWidgets('shows recently cached reviews as cards without refetching', (tester) async {
      await cache.write('reviews:1', const ReviewsPage(reviews: [_review], hasNextPage: true));

      await tester.pumpWidget(app(const ReviewsSection(mediaId: 1)));
      await tester.pump();

      expect(find.byType(ReviewCard), findsOneWidget);
      expect(find.text('Loved every minute'), findsOneWidget);
      expect(find.text('367'), findsOneWidget);
      expect(find.text('See all'), findsOneWidget);
      expect(offline.requests, 0, reason: 'reviews are cached for 6 hours');
    });

    testWidgets('opens the full review when a card is tapped', (tester) async {
      await cache.write('reviews:1', const ReviewsPage(reviews: [_review], hasNextPage: false));

      await tester.pumpWidget(app(const ReviewsSection(mediaId: 1)));
      await tester.pump();
      await tester.tap(find.text('Loved every minute'));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
    });
  });

  group('ReviewScreen', () {
    testWidgets('shows the cleaned body, score and likes of a cached review', (tester) async {
      await cache.write(
        'review:5',
        const Review(
          id: 5,
          user: MiniUser(id: 9, name: 'Ann'),
          summary: 'Loved every minute',
          rating: 367,
          ratingAmount: 781,
          score: 86,
          body: '# __Great__ show img(https://x.co/a.png)',
        ),
      );

      await tester.pumpWidget(app(const ReviewScreen(reviewId: 5), scroll: false));
      await tester.pump();

      expect(find.text('Ann'), findsOneWidget);
      expect(find.text('86/100'), findsOneWidget);
      expect(find.text('Great show'), findsOneWidget);
      expect(find.text(trf('review_liked_by', 'English', {'liked': 367, 'total': 781})), findsOneWidget);
      expect(offline.requests, 0);
    });

    testWidgets('shows an error with retry when offline and nothing is cached', (tester) async {
      await tester.pumpWidget(app(const ReviewScreen(reviewId: 5, initial: _review), scroll: false));
      await tester.pump();

      expect(find.text(loadErrorText), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(offline.requests, 2);
    });
  });

  group('ReviewsScreen', () {
    testWidgets('shows an error with retry when the first page fails', (tester) async {
      await tester.pumpWidget(app(const ReviewsScreen(mediaId: 1), scroll: false));
      await tester.pump();

      expect(find.text(loadErrorText), findsOneWidget);
      expect(offline.requests, 1);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(offline.requests, 2);
    });
  });

  group('FollowingSection', () {
    testWidgets('stays hidden and sends nothing when logged out', (tester) async {
      await tester.pumpWidget(app(const FollowingSection(mediaId: 1, isManga: false)));
      await tester.pump();

      expect(find.text('FOLLOWING'), findsNothing);
      expect(offline.requests, 0);
    });

    testWidgets('lists the first five friends with status and score, expanding to all', (tester) async {
      await cache.write(ApiCache.userKey(7, 'following:1'), [
        _entry(1, 'CURRENT', progress: 12, score: 8.5),
        _entry(2, 'COMPLETED', score: 9),
        for (var id = 3; id <= 7; id++) _entry(id, 'PLANNING'),
      ]);

      await tester.pumpWidget(app(const FollowingSection(mediaId: 1, isManga: false), auth: _LoggedInAuth()));
      await tester.pump();

      expect(find.text('FOLLOWING'), findsOneWidget);
      expect(find.text('Watching'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('8.5'), findsOneWidget);
      expect(find.text('9.0'), findsOneWidget);
      expect(find.textContaining('Friend '), findsNWidgets(5));
      expect(offline.requests, 1, reason: "friends' entries are always revalidated");

      await tester.tap(find.byType(TextButton));
      await tester.pump();

      expect(find.textContaining('Friend '), findsNWidgets(7));
    });

    testWidgets('words statuses for manga', (tester) async {
      await cache.write(ApiCache.userKey(7, 'following:2'), [
        _entry(1, 'CURRENT', progress: 30),
        _entry(2, 'REPEATING'),
      ]);

      await tester.pumpWidget(app(const FollowingSection(mediaId: 2, isManga: true), auth: _LoggedInAuth()));
      await tester.pump();

      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Rereading'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing, reason: 'five or fewer need no "show all"');
    });
  });
}
