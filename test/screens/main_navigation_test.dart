import 'package:anispark/main.dart';
import 'package:anispark/providers/media_list_store.dart';
import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/motion/liquid_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';

void main() {
  // The manga tab is used: a fresh anime list also reschedules episode
  // notifications, whose plugin isn't available under `flutter test`.
  testWidgets('the tabs open on the default tab with the bar at the bottom', (tester) async {
    SharedPreferences.setMockInitialValues({'defaultTab': 1});
    final settings = SettingsProvider();
    await settings.load();
    final cache = ApiCache(MemoryCacheStore());

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: cache),
        ChangeNotifierProvider<AuthService>(
          create: (_) => FakeAuthService(fakeToken: 'tok', fakeUser: {'id': 7, 'name': 'tester'}),
        ),
        ChangeNotifierProvider(
          create: (_) => MediaListStore(
            service: AniListService(
              client: mockAniList([], (_) => jsonResponse({
                    'data': {
                      'MediaListCollection': {'lists': []},
                    },
                  })),
            ),
            cache: cache,
          ),
        ),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark, settings.accentColor),
        home: const MainNavigation(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);

    final screen = tester.getSize(find.byType(MainNavigation));
    final bar = tester.getRect(find.byType(LiquidNavigationBar));
    expect(bar.bottom, screen.height, reason: 'docked at the bottom');
    expect(bar.height, lessThan(120), reason: 'it once filled the whole screen');
  });
}
