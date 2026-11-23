import 'dart:io';

import 'package:anispark/screens/profile_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

/// Logged in, following a few people, with a fresh cached profile.
class _FollowingAuth extends FakeAuthService {
  _FollowingAuth({this.count = 3, this.followers = 0, this.followerList})
      : super(fakeToken: 'token', fakeUser: {'id': 7, 'name': 'Faye'});

  final int count;
  final int followers;

  /// The followers kept with the profile; an older cache has none.
  final List<Map<String, dynamic>>? followerList;

  @override
  Map<String, dynamic>? get profileExtras => {
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'favoriteAnime': const [],
        'favoriteCharacters': const [],
        'followersCount': followers,
        'followingCount': count,
        'activityDays': const <String, dynamic>{},
        'following': [
          for (var i = 1; i <= count; i++)
            {'id': i, 'name': 'Friend $i', 'avatar': null},
        ],
        if (followerList != null) 'followers': followerList,
      };
}

void main() {
  // The followers are asked for with the shared client; keep it off the network.
  final offline = OfflineHttpOverrides();

  setUpAll(() => HttpOverrides.global = offline);

  setUp(() => offline.requests = 0);

  testWidgets('dragging the people up scrolls them inside the sheet, which stays put', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(const ProfileScreen(), cache: ApiCache(MemoryCacheStore()), auth: _FollowingAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3 Following'));
    await tester.pumpAndSettle();
    final title = find.text('Following');
    final top = tester.getTopLeft(title).dy;
    expect(top, greaterThan(47), reason: 'well clear of the status bar');

    // Like the Sort sheet: the list bounces, the sheet doesn't grow.
    final gesture = await tester.startGesture(tester.getCenter(find.text('Friend 1')));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getTopLeft(title).dy, top, reason: 'held up, the sheet stays where it was');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, top);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a long list keeps the sheet to most of the screen and scrolls inside it', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        appWith(const ProfileScreen(), cache: ApiCache(MemoryCacheStore()), auth: _FollowingAuth(count: 30)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('30 Following'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(tester.getTopLeft(find.text('Following')).dy, greaterThanOrEqualTo(900 * 0.3),
        reason: 'the sheet is at most 70% of the screen tall');
    expect(find.text('Friend 30'), findsNothing);

    await tester.scrollUntilVisible(find.text('Friend 30'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Friend 30'), findsOneWidget);
  });

  testWidgets('followers that could not be loaded say so, with a retry', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(const ProfileScreen(), cache: ApiCache(MemoryCacheStore()), auth: _FollowingAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('0 Followers'));
    await tester.pumpAndSettle();

    expect(find.text(loadErrorText), findsOneWidget);
    expect(find.text('Nobody here yet'), findsNothing, reason: 'not knowing is not the same as nobody');
    expect(offline.requests, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(offline.requests, 2);
    expect(find.text(loadErrorText), findsOneWidget);
  });

  testWidgets('followers show the shape of their rows, not a spinner, while they load', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(const ProfileScreen(), cache: ApiCache(MemoryCacheStore()), auth: _FollowingAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('0 Followers'));
    await tester.pump();

    expect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(PeopleSkeleton)), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(PeopleSkeleton), findsNothing);
  });

  testWidgets('followers loaded with the profile open at once, without asking again', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(
      const ProfileScreen(),
      cache: ApiCache(MemoryCacheStore()),
      auth: _FollowingAuth(followers: 2, followerList: [
        {'id': 21, 'name': 'Jet', 'avatar': null},
        {'id': 22, 'name': 'Ed', 'avatar': null},
      ]),
    ));
    await tester.pumpAndSettle();
    final before = offline.requests;

    await tester.tap(find.text('2 Followers'));
    await tester.pump();

    expect(find.text('Jet'), findsOneWidget, reason: 'there from the first frame');
    expect(find.byType(PeopleSkeleton), findsNothing);
    final opening = tester.getSize(find.byType(BottomSheet)).height;
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BottomSheet)).height, opening);
    expect(offline.requests, before);
  });

  testWidgets('a session whose user has not arrived yet shows the shape of the profile', (tester) async {
    await tester.pumpWidget(appWith(
      const ProfileScreen(),
      cache: ApiCache(MemoryCacheStore()),
      auth: FakeAuthService(fakeToken: 'token'),
    ));

    expect(find.byType(ProfileSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('the followers sheet opens without a step', () {
    Future<void> openFollowers(WidgetTester tester, {required int followers}) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(appWith(
        const ProfileScreen(),
        cache: ApiCache(MemoryCacheStore()),
        auth: _FollowingAuth(followers: followers),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('$followers Followers'));
      await tester.pump();
    }

    final placeholder = find.descendant(of: find.byType(BottomSheet), matching: find.byType(PeopleSkeleton));

    testWidgets('it is as tall as it will be from the start: a placeholder row per follower', (tester) async {
      await openFollowers(tester, followers: 5);

      expect(tester.widget<PeopleSkeleton>(placeholder).rows, 5);
    });

    testWidgets('the placeholder of some people is as tall as the list of as many', (tester) async {
      await openFollowers(tester, followers: 3);
      await tester.pump(const Duration(milliseconds: 100));
      final waiting = tester.getSize(find.byType(BottomSheet)).height;
      await tester.pumpAndSettle();
      Navigator.pop(tester.element(find.byType(BottomSheet)));
      await tester.pumpAndSettle();

      // The fixture follows three people, and those are already loaded.
      await tester.tap(find.text('3 Following'));
      await tester.pumpAndSettle();
      expect(find.text('Friend 3'), findsOneWidget);
      expect(tester.getSize(find.byType(BottomSheet)).height, waiting);
    });

    testWidgets('with many followers the placeholder stops at what the sheet can hold', (tester) async {
      await openFollowers(tester, followers: 400);

      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(BottomSheet)).height, lessThanOrEqualTo(900 * 0.7));
      await tester.pumpAndSettle();
    });

    testWidgets('what loads while it is still sliding up waits until it has arrived', (tester) async {
      await openFollowers(tester, followers: 5);
      await tester.pump(const Duration(milliseconds: 80));

      // Offline, so the answer (a failure) is in already; the sheet is not.
      expect(offline.requests, 1);
      expect(placeholder, findsOneWidget, reason: 'nothing is swapped mid-slide');
      expect(find.text(loadErrorText), findsNothing);
      final height = tester.getSize(find.byType(BottomSheet)).height;

      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getSize(find.byType(BottomSheet)).height, height, reason: 'the sheet keeps its height while it slides');

      await tester.pumpAndSettle();
      expect(placeholder, findsNothing);
      expect(find.text(loadErrorText), findsOneWidget);
    });
  });
}
