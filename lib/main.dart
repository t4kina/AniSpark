import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/anime_list_provider.dart';
import 'services/auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/my_list_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/feed_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final animeProvider = AnimeListProvider();
  await animeProvider.init();

  final authService = AuthService();
  await authService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: animeProvider),
        ChangeNotifierProvider.value(value: authService),
      ],
      child: const MyAnimeApp(),
    ),
  );
}

class MyAnimeApp extends StatelessWidget {
  const MyAnimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniSpark',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E0E2C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF02A9FF),
          surface: Color(0xFF13132A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0E0E2C),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF13132A),
          indicatorColor: const Color(0xFF02A9FF).withValues(alpha: 0.2),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF13132A),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.tv_outlined),
              selectedIcon: Icon(Icons.tv),
              label: 'Anime'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Manga'),
          NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Discover'),
          NavigationDestination(
              icon: Icon(Icons.whatshot_outlined),
              selectedIcon: Icon(Icons.whatshot),
              label: 'Feed'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
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