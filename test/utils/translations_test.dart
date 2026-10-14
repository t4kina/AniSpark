import 'package:anispark/utils/translations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // NOTE: a throwaway run (not committed) confirmed every one of the 8
  // languages in `translations` currently defines all 118 English keys
  // (0 missing, 0 extra, for every non-English language). That means the
  // "key missing in a *registered* language" branch of tr()'s fallback
  // expression is currently unreachable with real data — the only way to
  // exercise `translations[language]?[key] ?? translations['English']`
  // falling through to English today is via a `language` argument that
  // isn't registered at all. The tests below exercise that real path and
  // document why.

  test('returns the language-specific value when the key exists for that '
      'language', () {
    expect(tr('nav_discover', 'English'), 'Discover');
    expect(tr('nav_discover', 'Spanish'), 'Explorar');
    expect(tr('nav_discover', 'Japanese'), '探索');
  });

  test(
      'falls back to English when the language argument is not registered '
      '(every registered language currently defines every English key, so '
      'this is the only reachable trigger for that fallback)', () {
    expect(tr('nav_anime', 'Elvish'), tr('nav_anime', 'English'));
    expect(tr('nav_anime', 'Elvish'), 'Anime');
  });

  test('falls back to the key itself when the key is unknown in every '
      'language', () {
    const unknownKey = 'totally_unknown_key_123';

    expect(tr(unknownKey, 'English'), unknownKey);
    expect(tr(unknownKey, 'Spanish'), unknownKey);
  });

  test('falls back to the key itself when both the language and the key '
      'are unrecognized', () {
    const unknownKey = 'another_unknown_key_456';

    expect(tr(unknownKey, 'Elvish'), unknownKey);
  });

  test('an unknown language falls back to the English translation for a '
      'known key', () {
    expect(tr('nav_manga', 'Klingon'), 'Manga');
  });

  test('every language defines every English key, with the same placeholders', () {
    final english = translations['English']!;
    final placeholder = RegExp(r'\{(\w+)\}');
    Set<String> placeholdersOf(String text) => {for (final m in placeholder.allMatches(text)) m.group(1)!};

    for (final MapEntry(key: language, value: texts) in translations.entries) {
      expect(texts.keys.toSet().difference(english.keys.toSet()), isEmpty, reason: '$language has keys English lacks');
      expect(english.keys.toSet().difference(texts.keys.toSet()), isEmpty, reason: '$language is missing keys');
      for (final MapEntry(:key, :value) in english.entries) {
        expect(placeholdersOf(texts[key]!), placeholdersOf(value), reason: "$language '$key' placeholders");
      }
    }
  });

  test('tr resolves the same key independently per language', () {
    expect(tr('watching', 'English'), 'Watching');
    expect(tr('watching', 'Spanish'), 'Viendo');
    expect(tr('watching', 'German'), 'Schaue ich');
  });
}
