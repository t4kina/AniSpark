import 'dart:io';

import 'package:anispark/screens/user_profile_screen.dart';
import 'package:anispark/services/api_cache.dart';
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
}
