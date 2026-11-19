import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/friend_alerts.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/friend_alert_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';

String _en(String key, [Map<String, Object>? values]) =>
    values == null ? tr(key, 'English') : trf(key, 'English', values);

void main() {
  late FriendAlertsStore bells;
  late SettingsProvider settings;

  setUp(() async {
    // Notifications already allowed, so turning a bell on asks nothing.
    SharedPreferences.setMockInitialValues({'pushNotifications': true});
    bells = FriendAlertsStore();
    settings = SettingsProvider();
    await settings.load();
  });

  Future<void> pumpOpener(WidgetTester tester, void Function(BuildContext) open) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(
      Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () => open(context), child: const Text('open')))),
      cache: ApiCache(MemoryCacheStore()),
      settings: settings,
      friendAlerts: bells,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a friend\'s bell: each kind switches on and off at once, and it can be stopped', (tester) async {
    await pumpOpener(tester, (context) => showFriendAlertSheet(context, userId: 7, name: 'Faye'));

    expect(find.text(_en('bell_title', {'name': 'Faye'})), findsOneWidget);
    expect(find.text(_en('bell_off')), findsNothing, reason: 'nothing to stop yet');

    await tester.tap(find.text(_en('bell_progress')));
    await tester.pumpAndSettle();
    expect(bells.watchOf(7)!.kinds, {FriendAlertKind.progress});
    expect(find.descendant(of: find.byKey(const ValueKey('bell-progress')), matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);

    await tester.tap(find.text(_en('bell_text')));
    await tester.pumpAndSettle();
    expect(bells.watchOf(7)!.kinds, {FriendAlertKind.progress, FriendAlertKind.text});

    await tester.tap(find.text(_en('bell_off')));
    await tester.pumpAndSettle();
    expect(bells.watchOf(7), isNull);
  });

  testWidgets('the friends with a bell are listed, and a cross turns one off', (tester) async {
    await bells.watch(userId: 7, name: 'Faye', kinds: defaultFriendAlertKinds);
    await bells.watch(userId: 8, name: 'Jet', kinds: defaultFriendAlertKinds);
    await pumpOpener(tester, showFriendBellsSheet);

    expect(find.text('Faye'), findsOneWidget);
    expect(find.text('Jet'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('bell-friend-7')), matching: find.byIcon(Icons.close_rounded)));
    await tester.pumpAndSettle();
    expect(find.text('Faye'), findsNothing);
    expect(bells.watches.map((watch) => watch.userId), [8]);
  });

  testWidgets('without bells it says how to turn one on', (tester) async {
    await pumpOpener(tester, showFriendBellsSheet);

    expect(find.text(_en('settings_no_bells')), findsOneWidget);
  });
}
