import 'dart:io';

import 'package:anispark/screens/user_profile_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/detail/detail_labels.dart';
import 'package:anispark/widgets/profile/profile_card.dart';
import 'package:anispark/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

void main() {
  final offline = OfflineHttpOverrides();
  late ApiCache cache;

  setUpAll(() => HttpOverrides.global = offline);

  setUp(() {
    offline.requests = 0;
    cache = ApiCache(MemoryCacheStore());
  });

  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.pumpWidget(screenApp(
      const UserProfileScreen(userId: 7, name: 'faye'),
      cache: cache,
    ));
    // The profile loads from a post-frame callback.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows an error with retry when offline and nothing is cached',
      (tester) async {
    await pumpProfile(tester);

    expect(find.text(loadErrorText), findsOneWidget);
    expect(offline.requests, 2, reason: 'profile and recent activity');

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(offline.requests, 4);
    expect(find.text(loadErrorText), findsOneWidget);
  });

  testWidgets('shows the cached profile and activity when offline',
      (tester) async {
    await cache.write('anon:profile:7', {
      'id': 7,
      'name': 'Faye Valentine',
      'isFollowing': false,
      'isFollower': false,
    });
    final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
    await cache.write('anon:activity:7', [
      {'id': 1, 'type': 'TEXT', 'text': 'Jackpot!', 'createdAt': createdAt},
    ]);

    await pumpProfile(tester);

    expect(find.text('Faye Valentine'), findsOneWidget);
    expect(find.text('Jackpot!'), findsOneWidget);
    expect(find.text(loadErrorText), findsNothing);
  });

  testWidgets('the genres they watch most say so, each in its own colour', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await cache.write('anon:profile:7', {
      'id': 7,
      'name': 'Faye Valentine',
      'isFollowing': false,
      'isFollower': false,
      'statistics': {
        'anime': {
          'genres': [
            {'genre': 'Action', 'count': 12},
            {'genre': 'Romance', 'count': 30},
          ],
        },
      },
    });

    await pumpProfile(tester);

    expect(find.text(tr('profile_top_genres', 'English')), findsOneWidget);
    final chips = find.byType(GenreChips);
    expect(tester.widget<GenreChips>(chips).genres, ['Romance', 'Action'], reason: 'most watched first');
  });

  testWidgets('shows the shape of a profile, under the back button, while it loads', (tester) async {
    await tester.pumpWidget(screenApp(
      const UserProfileScreen(userId: 7, name: 'faye'),
      cache: cache,
    ));

    final loading = tester.widget<ProfileSkeleton>(find.byKey(const ValueKey('uprof-loading')));
    expect(loading.topGap, 52, reason: 'the room the card itself leaves for the back button');
    // Let the failed requests settle.
    await tester.pump();
    await tester.pump();
  });

  testWidgets('the list sheet shows the shape of its rows, not a spinner, while it loads', (tester) async {
    await cache.write('anon:profile:7', {
      'id': 7,
      'name': 'Faye Valentine',
      'isFollowing': false,
      'isFollower': false,
      'statistics': {
        'anime': {'count': 5},
      },
    });
    await pumpProfile(tester);

    await tester.tap(find.text('5 anime'));
    await tester.pump();

    final rows = tester.widget<ListSkeleton>(find.byType(ListSkeleton));
    expect(rows.coverSize, const Size(46, 64), reason: 'the size of the covers in this sheet');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(ListSkeleton), findsNothing);
    expect(find.text(loadErrorText), findsOneWidget);
  });

  testWidgets('an avatar that flies here lands where the card will have it, then on the card', (tester) async {
    const tag = 'person:feed-1:7';
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.reset);
    await cache.write('anon:profile:7', {
      'id': 7,
      'name': 'Faye Valentine',
      'isFollowing': false,
      'isFollower': false,
    });
    await tester.pumpWidget(screenApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const UserProfileScreen(
                userId: 7,
                name: 'faye',
                avatarUrl: 'https://img.example/faye.png',
                heroTag: tag,
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
      cache: cache,
    ));
    final avatar = find.descendant(of: find.byType(UserProfileScreen), matching: find.byType(Hero));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('uprof-loading')), findsOneWidget, reason: 'the placeholder holds the landing spot');
    expect(tester.widget<Hero>(avatar).tag, tag);
    // The placeholder puts it where the card says its avatar goes.
    final expected = ProfileCard.avatarRect(top: 47 + 52);
    Matcher near(Rect rect) => within<Rect>(distance: 0.01, from: rect);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('uprof-loading')), findsNothing);
    expect(find.text('Faye Valentine'), findsWidgets);
    expect(tester.widget<Hero>(avatar).tag, tag, reason: 'so the avatar can fly back');
    expect(tester.getRect(avatar), near(expected), reason: 'the card has it where it landed');
  });
}
