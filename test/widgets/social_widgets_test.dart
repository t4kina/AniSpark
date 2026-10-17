import 'package:anispark/widgets/social/social_widgets.dart';
import 'package:anispark/widgets/user_avatar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
