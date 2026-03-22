import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/anime_list_provider.dart';
import 'providers/settings_provider.dart';
import 'services/auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/my_list_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/feed_screen.dart';
import 'utils/translations.dart' show tr;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final animeProvider = AnimeListProvider();
  await animeProvider.init();

  final authService = AuthService();
  await authService.init();

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
        scaffoldBackgroundColor: const Color(0xFFF0F2FA),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF02A9FF),
          surface: Colors.white,
          surfaceContainerHighest: Color(0xFFE5E7F2),
          outline: Color(0xFFD0D2E4),
          onSurface: Color(0xFF1A1A2E),
          onSurfaceVariant: Colors.black54,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF0F2FA),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          foregroundColor: Color(0xFF1A1A2E),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          height: 64,
          indicatorColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF02A9FF));
            }
            return const IconThemeData(color: Colors.grey);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(color: Color(0xFF02A9FF), fontSize: 11, fontWeight: FontWeight.w600);
            }
            return const TextStyle(color: Colors.grey, fontSize: 11);
          }),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xFF02A9FF),
          unselectedLabelColor: Colors.grey,
          indicatorColor: Color(0xFF02A9FF),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFE5E7F2),
          labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF1A1A2E)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          side: const BorderSide(color: Color(0xFFD0D2E4)),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
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
            borderSide: const BorderSide(color: Color(0xFF02A9FF), width: 1),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: const TextStyle(color: Colors.grey),
        ),
        listTileTheme: const ListTileThemeData(
          tileColor: Colors.white,
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
        scaffoldBackgroundColor: const Color(0xFF0E0E2C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF02A9FF),
          surface: Color(0xFF13132A),
          surfaceContainerHighest: Color(0xFF1E1E3A),
          outline: Color(0xFF2A2A4A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0E0E2C),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF13132A),
          height: 64,
          indicatorColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF02A9FF));
            }
            return const IconThemeData(color: Colors.grey);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                  color: Color(0xFF02A9FF), fontSize: 11, fontWeight: FontWeight.w600);
            }
            return const TextStyle(color: Colors.grey, fontSize: 11);
          }),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xFF02A9FF),
          unselectedLabelColor: Colors.grey,
          indicatorColor: Color(0xFF02A9FF),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF1E1E3A),
          labelStyle: const TextStyle(fontSize: 11),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF13132A),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E3A),
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
            borderSide: const BorderSide(color: Color(0xFF02A9FF), width: 1),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: const TextStyle(color: Colors.grey),
        ),
        listTileTheme: const ListTileThemeData(
          tileColor: Color(0xFF13132A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF1E1E3A),
          thickness: 1,
          space: 0,
        ),
        fontFamily: 'Roboto',
      ),
      builder: (context, child) {
        return ScrollConfiguration(
          behavior: const _SmoothScrollBehavior(),
          child: child!,
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

  void _setTab(int index) => setState(() => _currentIndex = index);

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
        children: _screens,
      ),
      bottomNavigationBar: Consumer<SettingsProvider>(
        builder: (_, settings, _) => NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.tv_outlined),
                selectedIcon: const Icon(Icons.tv),
                label: tr('nav_anime', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.menu_book_outlined),
                selectedIcon: const Icon(Icons.menu_book),
                label: tr('nav_manga', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.explore_outlined),
                selectedIcon: const Icon(Icons.explore),
                label: tr('nav_discover', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.whatshot_outlined),
                selectedIcon: const Icon(Icons.whatshot),
                label: tr('nav_feed', settings.language)),
            NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
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