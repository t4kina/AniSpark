import 'dart:io';

import 'package:anispark/screens/user_profile_screen.dart';
import 'package:anispark/services/api_cache.dart';
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
}
