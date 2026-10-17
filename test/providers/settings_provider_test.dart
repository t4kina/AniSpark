import 'package:anispark/providers/settings_provider.dart';
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
      // NOTE: the in-class field defaults for these two flags are `true`
      // (settings_provider.dart:17-18), but load() falls back to `false`
      // when the key is absent (settings_provider.dart:54-55). This test
      // pins the *current* post-load() behavior.
      expect(provider.pushNotifications, isFalse);
      expect(provider.newEpisodeAlerts, isFalse);
      expect(provider.friendActivityAlerts, isFalse);
      expect(provider.accentColorName, 'Blue');
    });

    test('loads values previously stored in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'language': 'Spanish',
        'appearance': 'Light',
        'titleLanguage': 'Native',
        'pushNotifications': true,
        'newEpisodeAlerts': true,
        'friendActivityAlerts': true,
        'accentColorName': 'Purple',
      });
      final provider = SettingsProvider();

      await provider.load();

      expect(provider.language, 'Spanish');
      expect(provider.appearance, 'Light');
      expect(provider.titleLanguage, 'Native');
      expect(provider.pushNotifications, isTrue);
      expect(provider.newEpisodeAlerts, isTrue);
      expect(provider.friendActivityAlerts, isTrue);
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

    test('setPushNotifications updates the getter, persists it, and notifies',
        () async {
      final provider = SettingsProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setPushNotifications(false);

      expect(provider.pushNotifications, isFalse);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pushNotifications'), isFalse);
    });

    test('setNewEpisodeAlerts updates the getter, persists it, and notifies',
        () async {
      final provider = SettingsProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setNewEpisodeAlerts(false);

      expect(provider.newEpisodeAlerts, isFalse);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('newEpisodeAlerts'), isFalse);
    });

    test(
        'setFriendActivityAlerts updates the getter, persists it, and '
        'notifies', () async {
      final provider = SettingsProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setFriendActivityAlerts(true);

      expect(provider.friendActivityAlerts, isTrue);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('friendActivityAlerts'), isTrue);
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
}
