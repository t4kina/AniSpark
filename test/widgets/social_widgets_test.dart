import 'dart:io';

import 'package:anispark/screens/user_profile_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/widgets/motion/cover_hero.dart';
import 'package:anispark/widgets/social/social_widgets.dart';
import 'package:anispark/widgets/user_avatar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_cache_store.dart';
import '../screens/screen_harness.dart';

void main() {
  testWidgets(
    'ProfileAvatar has a 44x44 hit area without growing the drawn avatar',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ProfileAvatar(user: {'id': 1, 'name': 'a'}, radius: 16),
            ),
          ),
        ),
      );

      final hitArea = tester.getSize(find.byType(ProfileAvatar));
      expect(hitArea.width, greaterThanOrEqualTo(44));
      expect(hitArea.height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byType(UserAvatar)), const Size(32, 32));

      // A tap on the avatar's padding still lands on the button.
      final rect = tester.getRect(find.byType(ProfileAvatar));
      final avatarRect = tester.getRect(find.byType(UserAvatar));
      expect(rect.contains(avatarRect.topLeft - const Offset(3, 3)), isTrue);
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byType(ProfileAvatar)),
        matchesSemantics(label: 'a', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    },
  );

  testWidgets(
    'TappableUserName is at least 44px high, a button, and taps through',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: TappableUserName(
                onTap: () => taps++,
                child: const Text('someone'),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(TappableUserName)).height,
        greaterThanOrEqualTo(44),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byType(TappableUserName)),
        matchesSemantics(isButton: true, hasTapAction: true, label: 'someone'),
      );
      handle.dispose();

      final text = tester.getTopLeft(find.text('someone'));
      await tester.tapAt(text + const Offset(2, 20));
      expect(taps, 1, reason: 'a tap below the text still counts');
    },
  );

  testWidgets('UserAvatar decodes the image at its on-screen pixel size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: UserAvatar(url: 'https://example.com/a.png', size: 40),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, 120);
  });

  testWidgets('a user name dims while it is pressed and reports the tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: TappableUserName(onTap: () => taps++, child: const Text('Faye')))),
    ));
    double opacity() =>
        tester.widget<Opacity>(find.ancestor(of: find.text('Faye'), matching: find.byType(Opacity)).first).opacity;

    final gesture = await tester.startGesture(tester.getCenter(find.text('Faye')));
    await tester.pumpAndSettle();
    expect(opacity(), lessThan(0.6));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(taps, 1);
  });

  group('an avatar with a hero scope', () {
    const faye = {'id': 7, 'name': 'faye'};

    setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

    Widget page(List<Widget> avatars) => screenApp(
          Scaffold(body: Column(children: avatars)),
          cache: ApiCache(MemoryCacheStore()),
        );

    testWidgets('is told apart from the same person elsewhere on the page', (tester) async {
      await tester.pumpWidget(page(const [
        ProfileAvatar(user: faye, heroScope: 'feed-1'),
        ProfileAvatar(user: faye, heroScope: 'feed-2'),
        ProfileAvatar(user: faye),
      ]));

      final tags = tester.widgetList<Hero>(find.byType(Hero)).map((hero) => hero.tag).toList();
      expect(tags, [personHeroTag('feed-1', 7), personHeroTag('feed-2', 7)], reason: 'none without a scope');
    });

    testWidgets('opens the profile with its tag, so it flies there', (tester) async {
      await tester.pumpWidget(page(const [ProfileAvatar(user: faye, heroScope: 'feed-1')]));

      await tester.tap(find.byType(ProfileAvatar));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      final profile = tester.widget<UserProfileScreen>(find.byType(UserProfileScreen));
      expect(profile.userId, 7);
      expect(profile.heroTag, personHeroTag('feed-1', 7));
      await tester.pumpAndSettle();
    });

    testWidgets('a name beside it opens the profile with the same tag', (tester) async {
      await tester.pumpWidget(page([
        const ProfileAvatar(user: faye, heroScope: 'feed-1'),
        Builder(
          builder: (context) => TappableUserName(
            onTap: () => openUserProfile(context, faye, heroScope: 'feed-1'),
            child: const Text('faye'),
          ),
        ),
      ]));

      await tester.tap(find.text('faye'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(tester.widget<UserProfileScreen>(find.byType(UserProfileScreen)).heroTag, personHeroTag('feed-1', 7));
      await tester.pumpAndSettle();
    });
  });
}
