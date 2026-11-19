import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_palette.dart';
import '../utils/haptics.dart' as haptics;
import '../utils/translations.dart' show tr;

const accentColorOptions = <String, Color>{
  'Blue':   Color(0xFF02A9FF),
  'Purple': Color(0xFF9C27B0),
  'Green':  Color(0xFF4CAF50),
  'Pink':   Color(0xFFE91E63),
  'Teal':   Color(0xFF009688),
  'Orange': Color(0xFFFF6B35),
};

class SettingsProvider extends ChangeNotifier {
  String _language = 'English';
  String _appearance = 'Dark';
  String _titleLanguage = 'English';
  bool _episodeAlerts = false;
  String _accentColorName = 'Blue';
  String _themeName = classicTheme;
  // Index into MainNavigation's tabs: Anime, Manga, Discover, Feed, Profile.
  // Anime, where the app has always opened.
  int _defaultTab = 0;
  bool _hapticsEnabled = true;

  String get language => _language;
  String get appearance => _appearance;
  String get titleLanguage => _titleLanguage;
  /// The one notification setting: a notice when a new episode of
  /// something being watched airs.
  bool get episodeAlerts => _episodeAlerts;
  String get accentColorName => _accentColorName;
  int get defaultTab => _defaultTab;
  bool get hapticsEnabled => _hapticsEnabled;

  /// One of [appThemes].
  String get themeName => _themeName;
  AppPalette get palette => appThemes[_themeName] ?? appThemes[classicTheme]!;

  /// The theme's own accent, or the one picked in Settings.
  Color get accentColor => palette.accent ?? accentColorOptions[_accentColorName] ?? const Color(0xFF02A9FF);

  /// Appearance, for a theme that comes in light; dark otherwise.
  ThemeMode get themeMode => !palette.hasLight
      ? ThemeMode.dark
      : switch (_appearance) {
          'Light' => ThemeMode.light,
          'System' => ThemeMode.system,
          _ => ThemeMode.dark,
        };

  /// Returns the AniList title field key based on preference.
  String resolveTitle(Map<String, dynamic>? titleMap) {
    final unknown = tr('feed_unknown', _language);
    if (titleMap == null) return unknown;
    switch (_titleLanguage) {
      case 'Romaji':
        return (titleMap['romaji'] ?? titleMap['english'] ?? unknown) as String;
      case 'Native':
        return (titleMap['native'] ?? titleMap['romaji'] ?? unknown) as String;
      default: // English
        return (titleMap['english'] ?? titleMap['romaji'] ?? unknown) as String;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString('language') ?? 'English';
    _appearance = prefs.getString('appearance') ?? 'Dark';
    _titleLanguage = prefs.getString('titleLanguage') ?? 'English';
    // Before, two switches had to be on together for the same notices.
    _episodeAlerts = prefs.getBool(_episodeAlertsKey) ??
        ((prefs.getBool(_oldPushKey) ?? false) && (prefs.getBool(_oldEpisodesKey) ?? false));
    _accentColorName = prefs.getString('accentColorName') ?? 'Blue';
    _themeName = appThemes.containsKey(prefs.getString('theme')) ? prefs.getString('theme')! : classicTheme;
    _defaultTab = prefs.getInt('defaultTab') ?? 0;
    _hapticsEnabled = prefs.getBool('hapticsEnabled') ?? true;
    haptics.hapticsEnabled = _hapticsEnabled;
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    _language = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', value);
    notifyListeners();
  }

  Future<void> setAppearance(String value) async {
    _appearance = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appearance', value);
    notifyListeners();
  }

  Future<void> setTitleLanguage(String value) async {
    _titleLanguage = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('titleLanguage', value);
    notifyListeners();
  }

  static const _episodeAlertsKey = 'episodeAlerts';
  static const _oldPushKey = 'pushNotifications';
  static const _oldEpisodesKey = 'newEpisodeAlerts';

  Future<void> setEpisodeAlerts(bool value) async {
    _episodeAlerts = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_episodeAlertsKey, value);
    await prefs.remove(_oldPushKey);
    await prefs.remove(_oldEpisodesKey);
    notifyListeners();
  }

  Future<void> setTheme(String name) async {
    if (!appThemes.containsKey(name)) return;
    _themeName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', name);
    notifyListeners();
  }

  Future<void> setAccentColor(String name) async {
    if (!accentColorOptions.containsKey(name)) return;
    _accentColorName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accentColorName', name);
    notifyListeners();
  }

  Future<void> setDefaultTab(int index) async {
    _defaultTab = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('defaultTab', index);
    notifyListeners();
  }

  Future<void> setHapticsEnabled(bool value) async {
    _hapticsEnabled = value;
    haptics.hapticsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hapticsEnabled', value);
    notifyListeners();
  }
}
