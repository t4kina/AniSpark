import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('load', () {
    test('uses documented defaults when prefs are empty', () async {
      final provider = SettingsProvider();

      await provider.load();

      expect(provider.language, 'English');
      expect(provider.appearance, 'Dark');
      expect(provider.titleLanguage, 'English');
      // Notifications stay off until asked for, with the permission.
      expect(provider.episodeAlerts, isFalse);
      expect(provider.accentColorName, 'Blue');
    });

    test('loads values previously stored in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'language': 'Spanish',
        'appearance': 'Light',
        'titleLanguage': 'Native',
        'episodeAlerts': true,
        'accentColorName': 'Purple',
      });
      final provider = SettingsProvider();

      await provider.load();

      expect(provider.language, 'Spanish');
      expect(provider.appearance, 'Light');
      expect(provider.titleLanguage, 'Native');
      expect(provider.episodeAlerts, isTrue);
      expect(provider.accentColorName, 'Purple');
    });

    test('notifies listeners exactly once', () async {
      final provider = SettingsProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.load();

      expect(notified, 1);
    });
  });

  group('setters', () {
    test('setLanguage updates the getter, persists it, and notifies',
        () async {
      final provider = SettingsProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setLanguage('French');

      expect(provider.language, 'French');
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('language'), 'French');
    });

    test('setAppearance updates the getter, persists it, and notifies',
        () async {
      final provider = SettingsProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setAppearance('Light');

      expect(provider.appearance, 'Light');
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appearance'), 'Light');
    });

    test('setTitleLanguage updates the getter, persists it, and notifies',
        () async {
      final provider = SettingsProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setTitleLanguage('Romaji');

      expect(provider.titleLanguage, 'Romaji');
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('titleLanguage'), 'Romaji');
    });

    test('setEpisodeAlerts updates the getter, persists it, and notifies',
        () async {
      final provider = SettingsProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setEpisodeAlerts(true);

      expect(provider.episodeAlerts, isTrue);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('episodeAlerts'), isTrue);
    });

    test('the two old switches become one: on only when both were on',
        () async {
      for (final (push, episodes, expected) in [
        (true, true, true),
        (true, false, false),
        (false, true, false),
        (null, null, false),
      ]) {
        SharedPreferences.setMockInitialValues({
          'pushNotifications': ?push,
          'newEpisodeAlerts': ?episodes,
        });
        final provider = SettingsProvider();

        await provider.load();

        expect(provider.episodeAlerts, expected, reason: 'push $push, episodes $episodes');
      }
    });

    test('once the one switch is set, the old ones are forgotten', () async {
      SharedPreferences.setMockInitialValues({'pushNotifications': true, 'newEpisodeAlerts': true});
      final provider = SettingsProvider();
      await provider.load();

      await provider.setEpisodeAlerts(false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('pushNotifications'), isFalse);
      expect(prefs.containsKey('newEpisodeAlerts'), isFalse);
      await provider.load();
      expect(provider.episodeAlerts, isFalse);
    });

    test('setAccentColor updates the getter, persists it, and notifies',
        () async {
      final provider = SettingsProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setAccentColor('Green');

      expect(provider.accentColorName, 'Green');
      expect(provider.accentColor, accentColorOptions['Green']);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('accentColorName'), 'Green');
    });

    test('setAccentColor with an unknown name changes nothing', () async {
      final provider = SettingsProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setAccentColor('Nope');

      expect(provider.accentColorName, 'Blue');
      expect(notified, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('accentColorName'), isNull);
    });
  });

  group('resolveTitle', () {
    test('returns Unknown for a null title map', () {
      final provider = SettingsProvider();

      expect(provider.resolveTitle(null), 'Unknown');
    });

    group('English (default titleLanguage)', () {
      test('returns the english title when present', () {
        final provider = SettingsProvider();

        expect(
          provider.resolveTitle(
              {'english': 'E', 'romaji': 'R', 'native': 'N'}),
          'E',
        );
      });

      test('falls back to romaji when english is missing', () {
        final provider = SettingsProvider();

        expect(
          provider.resolveTitle({'romaji': 'R', 'native': 'N'}),
          'R',
        );
      });

      test('falls back to Unknown when english and romaji are missing', () {
        final provider = SettingsProvider();

        expect(provider.resolveTitle({'native': 'N'}), 'Unknown');
      });
    });

    group('Romaji', () {
      test('returns the romaji title when present', () async {
        final provider = SettingsProvider();
        await provider.setTitleLanguage('Romaji');

        expect(
          provider.resolveTitle({'romaji': 'R', 'english': 'E'}),
          'R',
        );
      });

      test('falls back to english when romaji is missing', () async {
        final provider = SettingsProvider();
        await provider.setTitleLanguage('Romaji');

        expect(
          provider.resolveTitle({'english': 'E', 'native': 'N'}),
          'E',
        );
      });

      test('falls back to Unknown when romaji and english are missing',
          () async {
        final provider = SettingsProvider();
        await provider.setTitleLanguage('Romaji');

        expect(provider.resolveTitle({'native': 'N'}), 'Unknown');
      });
    });

    group('Native', () {
      test('returns the native title when present', () async {
        final provider = SettingsProvider();
        await provider.setTitleLanguage('Native');

        expect(
          provider.resolveTitle({'native': 'N', 'romaji': 'R'}),
          'N',
        );
      });

      test('falls back to romaji when native is missing', () async {
        final provider = SettingsProvider();
        await provider.setTitleLanguage('Native');

        expect(
          provider.resolveTitle({'romaji': 'R', 'english': 'E'}),
          'R',
        );
      });

      test('falls back to Unknown when native and romaji are missing',
          () async {
        final provider = SettingsProvider();
        await provider.setTitleLanguage('Native');

        expect(provider.resolveTitle({'english': 'E'}), 'Unknown');
      });
    });
  });

  group('themeMode', () {
    test('returns ThemeMode.dark by default', () {
      final provider = SettingsProvider();

      expect(provider.themeMode, ThemeMode.dark);
    });

    test('returns ThemeMode.light when appearance is Light', () async {
      final provider = SettingsProvider();
      await provider.setAppearance('Light');

      expect(provider.themeMode, ThemeMode.light);
    });

    test('returns ThemeMode.dark for any unrecognized appearance value',
        () async {
      final provider = SettingsProvider();
      await provider.setAppearance('Sepia');

      expect(provider.themeMode, ThemeMode.dark);
    });
  });

  group('themes', () {
    test('the app starts on the classic theme, with the accent picked in Settings', () async {
      final provider = SettingsProvider();
      await provider.load();

      expect(provider.themeName, classicTheme);
      expect(provider.palette, appThemes[classicTheme]);
      expect(provider.accentColor, accentColorOptions['Blue']);
    });

    test('a theme is kept, and comes back after a restart', () async {
      final provider = SettingsProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setTheme('Lilac');

      expect(provider.themeName, 'Lilac');
      expect(notified, 1);
      final restarted = SettingsProvider();
      await restarted.load();
      expect(restarted.themeName, 'Lilac');
    });

    test('a theme that is not one of the app\'s is ignored', () async {
      final provider = SettingsProvider();

      await provider.setTheme('Neon');

      expect(provider.themeName, classicTheme);
    });

    test('a theme with its own accent and no light version sets both', () async {
      final provider = SettingsProvider();
      await provider.setAppearance('Light');
      await provider.setAccentColor('Green');

      await provider.setTheme('Lilac');

      expect(provider.accentColor, appThemes['Lilac']!.accent);
      expect(provider.themeMode, ThemeMode.dark);
    });

    test('pure black keeps the accent picked in Settings', () async {
      final provider = SettingsProvider();
      await provider.setAccentColor('Pink');

      await provider.setTheme('Black');

      expect(appThemes['Black']!.accent, isNull);
      expect(provider.accentColor, accentColorOptions['Pink']);
    });
  });
}
