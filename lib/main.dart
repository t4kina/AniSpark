import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/anime_list_provider.dart';
import 'providers/settings_provider.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'screens/my_list_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/feed_screen.dart';
import 'utils/translations.dart' show tr;
import 'utils/refresh_notifier.dart' show authExpiredNotifier, rateLimitActiveNotifier;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final animeProvider = AnimeListProvider();
  await animeProvider.init();

  final authService = AuthService();
  await authService.init();

  await NotificationService().init();

  authExpiredNotifier.addListener(() => authService.logout());

  final settingsProvider = SettingsProvider();
  await settingsProvider.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: animeProvider),
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: settingsProvider),
      ],
      child: const MyAnimeApp(),
    ),
  );
}

class MyAnimeApp extends StatelessWidget {
  const MyAnimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return MaterialApp(
      title: 'AniSpark',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        visualDensity: VisualDensity.compact,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        scaffoldBackgroundColor: const Color(0xFFD8D8DC),
        colorScheme: ColorScheme.light(
          primary: settings.accentColor,
          surface: const Color(0xFFE2E2E6),
          surfaceContainerHighest: const Color(0xFFD0D0D4),
          outline: const Color(0xFFB8B8BC),
          onSurface: const Color(0xFF1A1A2E),
          onSurfaceVariant: Colors.black54,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFD8D8DC),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          foregroundColor: Color(0xFF1A1A2E),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFFEFEFF1),
          height: 64,
          indicatorColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(color: settings.accentColor);
            }
            return const IconThemeData(color: Colors.grey);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return TextStyle(color: settings.accentColor, fontSize: 11, fontWeight: FontWeight.w600);
            }
            return const TextStyle(color: Colors.grey, fontSize: 11);
          }),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: settings.accentColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: settings.accentColor,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFE5E7F2),
          labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF1A1A2E)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          side: const BorderSide(color: Color(0xFFD0D2E4)),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFE2E2E6),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFE8EAF4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: settings.accentColor, width: 1),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: const TextStyle(color: Colors.grey),
        ),
        listTileTheme: const ListTileThemeData(
          tileColor: Color(0xFFE2E2E6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFD0D2E4),
          thickness: 1,
          space: 0,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        ),
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        visualDensity: VisualDensity.compact,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        scaffoldBackgroundColor: const Color(0xFF111113),
        colorScheme: ColorScheme.dark(
          primary: settings.accentColor,
          surface: const Color(0xFF1C1C1E),
          surfaceContainerLow: const Color(0xFF1C1C1E),
          surfaceContainerHighest: const Color(0xFF2C2C2E),
          outlineVariant: const Color(0xFF38383A),
          outline: const Color(0xFF48484A),
          onSurface: const Color(0xFFEAEAEA),
          onSurfaceVariant: const Color(0xFFAAAAAA),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111113),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF1C1C1E),
          height: 64,
          indicatorColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(color: settings.accentColor);
            }
            return const IconThemeData(color: Colors.grey);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return TextStyle(color: settings.accentColor, fontSize: 11, fontWeight: FontWeight.w600);
            }
            return const TextStyle(color: Colors.grey, fontSize: 11);
          }),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: settings.accentColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: settings.accentColor,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF2C2C2E),
          labelStyle: const TextStyle(fontSize: 11),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1C1C1E),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2C2C2E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: settings.accentColor, width: 1),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: const TextStyle(color: Colors.grey),
        ),
        listTileTheme: const ListTileThemeData(
          tileColor: Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF2C2C2E),
          thickness: 1,
          space: 0,
        ),
        fontFamily: 'Roboto',
      ),
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
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await NotificationService().requestOnFirstLaunch(
        context.read<SettingsProvider>(),
      );
    });

    Future.delayed(const Duration(seconds: 2), () {
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
          (i) => _visited.contains(i) ? _screens[i] : const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: Consumer<SettingsProvider>(
        builder: (_, settings, _) => NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() {
            _currentIndex = i;
            _visited.add(i);
          }),
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.smart_display_outlined),
                selectedIcon: const Icon(Icons.smart_display),
                label: tr('nav_anime', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.collections_bookmark_outlined),
                selectedIcon: const Icon(Icons.collections_bookmark),
                label: tr('nav_manga', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.travel_explore_outlined),
                selectedIcon: const Icon(Icons.travel_explore),
                label: tr('nav_discover', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.article_outlined),
                selectedIcon: const Icon(Icons.article),
                label: tr('nav_feed', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.person_outline_rounded),
                selectedIcon: const Icon(Icons.person_rounded),
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
                    'Rate limit reached',
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