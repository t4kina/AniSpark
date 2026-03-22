import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  String _language = 'English';
  String _appearance = 'Dark';
  String _titleLanguage = 'English';

  String get language => _language;
  String get appearance => _appearance;
  String get titleLanguage => _titleLanguage;

  ThemeMode get themeMode => switch (_appearance) {
    'Light' => ThemeMode.light,
    _ => ThemeMode.dark,
  };

  /// Returns the AniList title field key based on preference.
  String resolveTitle(Map<String, dynamic>? titleMap) {
    if (titleMap == null) return 'Unknown';
    switch (_titleLanguage) {
      case 'Romaji':
        return (titleMap['romaji'] ?? titleMap['english'] ?? 'Unknown') as String;
      case 'Native':
        return (titleMap['native'] ?? titleMap['romaji'] ?? 'Unknown') as String;
      default: // English
        return (titleMap['english'] ?? titleMap['romaji'] ?? 'Unknown') as String;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString('language') ?? 'English';
    _appearance = prefs.getString('appearance') ?? 'Dark';
    _titleLanguage = prefs.getString('titleLanguage') ?? 'English';
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
}
