import 'package:anispark/services/people_api.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/people/people_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compactCount shortens thousands and millions', () {
    expect(compactCount(763), '763');
    expect(compactCount(1000), '1K');
    expect(compactCount(12345), '12.3K');
    expect(compactCount(20044), '20K');
    expect(compactCount(150400), '150K');
    expect(compactCount(1234567), '1.2M');
  });

  test('genderLabel translates the usual values and keeps the rest', () {
    expect(genderLabel('Female', 'English'), 'Female');
    expect(genderLabel('male', 'Spanish'), tr('char_gender_male', 'Spanish'));
    expect(genderLabel('Agender', 'English'), 'Agender');
  });

  test('labels for roles, formats and dub languages', () {
    expect(characterRoleLabel('MAIN', 'English'), 'main');
    expect(characterRoleLabel('EXTRA', 'English'), isNull);
    expect(mediaFormatLabel('MOVIE', 'English'), 'Movie');
    expect(mediaFormatLabel('OVA', 'English'), 'OVA');
    expect(mediaFormatAndYear(const MediaRef(id: 1, format: 'TV', startYear: 2006), 'English'), 'TV · 2006');
    expect(mediaFormatAndYear(const MediaRef(id: 1), 'English'), '');
    expect(voiceLanguageLabel('Japanese', 'Spanish'), tr('staff_lang_japanese', 'Spanish'));
    expect(voiceLanguageLabel('Tagalog', 'Spanish'), 'Tagalog');
    expect(voiceLanguageLabel(null, 'English'), '');
  });
}
