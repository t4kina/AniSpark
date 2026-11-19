import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/friend_alerts.dart';
import 'package:anispark/widgets/friend_alerts_watcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';

/// Counts the looks instead of asking AniList.
class _CountingChecker extends FriendAlertsChecker {
  int looks = 0;

  @override
  Future<List<Map<String, dynamic>>> newActivities(FriendAlertsStore store, {required String token}) async {
    looks++;
    return const [];
  }
}

void main() {
  late FriendAlertsStore bells;
  late _CountingChecker checker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bells = FriendAlertsStore();
    checker = _CountingChecker();
  });

  Future<void> pumpWatcher(WidgetTester tester, {bool loggedIn = true}) async {
    await tester.pumpWidget(appWith(
      FriendAlertsWatcher(checker: checker, child: const SizedBox()),
      cache: ApiCache(MemoryCacheStore()),
      auth: loggedIn ? FakeAuthService(fakeToken: 'tok', fakeUser: {'id': 1}) : null,
      friendAlerts: bells,
    ));
    await tester.pump();
  }

  testWidgets('looks once the app opens, and not again right after it comes back', (tester) async {
    await bells.watch(userId: 7, name: 'Faye', kinds: defaultFriendAlertKinds);
    await pumpWatcher(tester);
    expect(checker.looks, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(checker.looks, 1, reason: 'too soon after the last look');
  });

  testWidgets('without bells, or logged out, it does not look', (tester) async {
    await pumpWatcher(tester);
    expect(checker.looks, 0);

    await bells.watch(userId: 7, name: 'Faye', kinds: defaultFriendAlertKinds);
    await pumpWatcher(tester, loggedIn: false);
    expect(checker.looks, 0);
  });
}
