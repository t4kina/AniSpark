import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/media_list_store.dart';
import 'providers/settings_provider.dart';
import 'services/affinity_api.dart';
import 'services/anilist_service.dart';
import 'services/api_cache.dart';
import 'services/auth_service.dart';
import 'services/hive_cache_store.dart';
import 'services/notification_service.dart';
import 'services/secure_store.dart';
import 'services/session_expiry.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart' show recentSearchesPrefsKey;
import 'screens/my_list_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/feed_screen.dart';
import 'theme/app_theme.dart';
import 'utils/translations.dart' show tr;
import 'utils/refresh_notifier.dart' show rateLimitActiveNotifier;
import 'utils/tab_reselect.dart';
import 'widgets/motion/pop_in.dart';
import 'widgets/motion/tab_fade_through.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  unawaited(_deleteLegacyListBox());
  final settingsProvider = SettingsProvider();
  // AES key for the local boxes, kept in the platform keystore. Null when the
  // keystore can't be used (and on web): storage then stays unencrypted
  // exactly as before instead of failing. Loaded alongside the work that
  // doesn't need it, to keep startup fast.
  final (storageCipher, _, _) = await (
    kIsWeb ? Future<HiveAesCipher?>.value() : loadStorageCipher(const DeviceSecureStore()),
    NotificationService().init(),
    settingsProvider.load(),
  ).wait;
  final apiCache = ApiCache(await HiveCacheStore.openOrFallback(cipher: storageCipher));
  unawaited(apiCache.prune(maxAge: const Duration(days: 14), maxEntries: 300));

  final authService = AuthService();
  await authService.init(cipher: storageCipher);

  final mediaListStore = MediaListStore(service: AniListService(), cache: apiCache);
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  // A 401 means AniList no longer accepts the token (expired or revoked);
  // only a rejection of the current session's token logs it out.
  watchSessionExpiry(authService, onExpired: () {
    messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(tr('session_expired', settingsProvider.language))),
    );
  });
  // Everything stored for the account goes away when its session ends.
  var wasLoggedIn = authService.isLoggedIn;
  authService.addListener(() {
    final loggedIn = authService.isLoggedIn;
    if (wasLoggedIn && !loggedIn) unawaited(_clearAccountData(apiCache, mediaListStore));
    wasLoggedIn = loggedIn;
  });
  // Leftovers of a logout that was interrupted, e.g. by the app being killed.
  if (!authService.isLoggedIn) unawaited(apiCache.clear());

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: apiCache),
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: mediaListStore),
        ChangeNotifierProvider.value(value: settingsProvider),
      ],
      child: MyAnimeApp(scaffoldMessengerKey: messengerKey),
    ),
  );
}

/// Removes everything tied to the account that just logged out. Each step is
/// best effort and independent, so one failure doesn't skip the others.
Future<void> _clearAccountData(ApiCache cache, MediaListStore store) async {
  store.reset();
  await _bestEffort('clearing the affinity memo', () async => AffinityApi.clearViewerMemo());
  await _bestEffort('clearing the API cache', cache.clear);
  await _bestEffort('resetting notifications', NotificationService().resetForLogout);
  await _bestEffort('clearing recent searches', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(recentSearchesPrefsKey);
  });
}

Future<void> _bestEffort(String what, Future<void> Function() step) async {
  try {
    await step();
  } on Object catch (e) {
    // The session itself is already gone; leftovers are retried next logout.
    debugPrint('[Logout] Failed $what: $e');
  }
}

/// Removes the old local-only list box. It only mirrored AniList entries and
/// was never shown anywhere, so there is nothing to migrate.
Future<void> _deleteLegacyListBox() async {
  try {
    await Hive.deleteBoxFromDisk('myAnimeList');
  } on Object catch (e) {
    // Best-effort cleanup (Hive errors are Errors, not Exceptions).
    debugPrint('[Startup] Could not delete legacy list box: $e');
  }
}

class MyAnimeApp extends StatelessWidget {
  const MyAnimeApp({super.key, this.scaffoldMessengerKey});

  /// Lets app-wide events (e.g. an expired session) show a SnackBar.
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'AniSpark',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildAppTheme(Brightness.light, settings.accentColor),
      darkTheme: buildAppTheme(Brightness.dark, settings.accentColor),
      builder: (context, child) {
        return ScrollConfiguration(
          behavior: const _SmoothScrollBehavior(),
          child: _RateLimitBannerWrapper(child: child!),
        );
      },
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await NotificationService().requestOnFirstLaunch(
        context.read<SettingsProvider>(),
      );
    });

    // Everything needed to render is already loaded (cached lists and
    // profile), so the splash only stays long enough for the logo fade.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => MainNavigation(key: MainNavigation.globalKey),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/logo.jpg',
              width: 140,
              height: 140,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  static final globalKey = GlobalKey<_MainNavigationState>();

  static void navigateToTab(int index) {
    globalKey.currentState?._setTab(index);
  }

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final Set<int> _visited = {0};

  void _setTab(int index) => setState(() {
    _currentIndex = index;
    _visited.add(index);
  });

  void _onDestinationSelected(int index) {
    if (index == _currentIndex) {
      // Tapping the open tab again takes it back to the top.
      tabReselectedNotifier.reselect(index);
      return;
    }
    HapticFeedback.selectionClick();
    _setTab(index);
  }

  final List<Widget> _screens = const [
    AnimeListScreen(),
    MangaListScreen(),
    HomeScreen(),
    FeedScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(
          _screens.length,
          (i) => _visited.contains(i)
              ? TabFadeThrough(active: i == _currentIndex, child: _screens[i])
              : const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: Consumer<SettingsProvider>(
        builder: (_, settings, _) => NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.smart_display_outlined),
                selectedIcon: const PopIn(child: Icon(Icons.smart_display)),
                label: tr('nav_anime', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.collections_bookmark_outlined),
                selectedIcon: const PopIn(child: Icon(Icons.collections_bookmark)),
                label: tr('nav_manga', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.travel_explore_outlined),
                selectedIcon: const PopIn(child: Icon(Icons.travel_explore)),
                label: tr('nav_discover', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.article_outlined),
                selectedIcon: const PopIn(child: Icon(Icons.article)),
                label: tr('nav_feed', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.person_outline_rounded),
                selectedIcon: const PopIn(child: Icon(Icons.person_rounded)),
                label: tr('nav_profile', settings.language)),
          ],
        ),
      ),
    );
  }
}

class _SmoothScrollBehavior extends ScrollBehavior {
  const _SmoothScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}

class _RateLimitBannerWrapper extends StatefulWidget {
  final Widget child;
  const _RateLimitBannerWrapper({required this.child});

  @override
  State<_RateLimitBannerWrapper> createState() => _RateLimitBannerWrapperState();
}

class _RateLimitBannerWrapperState extends State<_RateLimitBannerWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _slide = Tween(begin: const Offset(0, 1.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    rateLimitActiveNotifier.addListener(_onRateLimitChanged);
  }

  @override
  void dispose() {
    rateLimitActiveNotifier.removeListener(_onRateLimitChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onRateLimitChanged() {
    if (!mounted) return;
    if (rateLimitActiveNotifier.value) {
      if (!_ctrl.isCompleted) _ctrl.forward();
    } else {
      if (!_ctrl.isDismissed) _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 64 + 12,
          left: 0,
          right: 0,
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tr('rate_limit_banner', context.select<SettingsProvider, String>((s) => s.language)),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
