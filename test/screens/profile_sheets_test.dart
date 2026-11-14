import 'package:anispark/screens/profile_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';

/// Logged in, following a few people, with a fresh cached profile.
class _FollowingAuth extends FakeAuthService {
  _FollowingAuth() : super(fakeToken: 'token', fakeUser: {'id': 7, 'name': 'Faye'});

  @override
  Map<String, dynamic>? get profileExtras => {
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'favoriteAnime': const [],
        'favoriteCharacters': const [],
        'followersCount': 0,
        'followingCount': 3,
        'activityDays': const <String, dynamic>{},
        'following': [
          for (var i = 1; i <= 3; i++)
            {'id': i, 'name': 'Friend $i', 'avatar': null},
        ],
      };
}

void main() {
  testWidgets('a list sheet dragged all the way up stops right under the status bar', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(const ProfileScreen(), cache: ApiCache(MemoryCacheStore()), auth: _FollowingAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3 Following'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Friend 1'), const Offset(0, -900));
    await tester.pumpAndSettle();

    final sheet = find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Container)).first;
    expect(tester.getTopLeft(sheet).dy, 47,
        reason: 'nothing behind the sheet shows above it, and it stays out of the status bar');
  });
}
