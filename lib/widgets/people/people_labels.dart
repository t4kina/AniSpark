import '../../services/people_api.dart';
import '../../utils/translations.dart';

/// "763", "12.3K", "1.2M": counts that fit in a pill.
String compactCount(int count) {
  String scaled(double value, String suffix) =>
      '${value.toStringAsFixed(value >= 100 ? 0 : 1).replaceAll(RegExp(r'\.0$'), '')}$suffix';
  if (count >= 1000000) return scaled(count / 1000000, 'M');
  if (count >= 1000) return scaled(count / 1000, 'K');
  return '$count';
}

/// AniList's gender is free text; the common values are translated and
/// anything else is shown as written.
String genderLabel(String gender, String lang) => switch (gender.toLowerCase()) {
      'male' => tr('char_gender_male', lang),
      'female' => tr('char_gender_female', lang),
      'non-binary' => tr('char_gender_non_binary', lang),
      _ => gender,
    };

/// A [date] as "17 Jun 1961", "Jun 17" (without the year, or when
/// [withYear] is false), "Jun 1961" or "1961"; null when there's nothing
/// to show.
String? fuzzyDateLabel(FuzzyDate? date, String lang, {bool withYear = true}) {
  if (date == null) return null;
  final year = withYear ? date.year : null;
  final month = date.month;
  final day = date.day;
  final monthName = month == null ? '' : tr('detail_month_$month', lang);
  if (year == null) {
    if (month == null && day == null) return null;
    if (day == null) return monthName;
    // Trimmed so a birthday without a month doesn't keep the separator.
    return trf('char_birthday_date', lang, {'month': monthName, 'day': day}).trim();
  }
  if (month == null) return '$year';
  if (day == null) return trf('detail_date_month_year', lang, {'month': monthName, 'year': year});
  return trf('detail_date_full', lang, {'day': day, 'month': monthName, 'year': year});
}

/// "main" / "supporting" / "background" for an AniList CharacterRole.
String? characterRoleLabel(String? role, String lang) => switch (role) {
      'MAIN' => tr('detail_role_main', lang),
      'SUPPORTING' => tr('detail_role_supporting', lang),
      'BACKGROUND' => tr('detail_role_background', lang),
      _ => null,
    };

/// An AniList MediaFormat; TV, OVA and ONA read the same in every language
/// and fall through (like the detail screen).
String mediaFormatLabel(String format, String lang) => switch (format) {
      'MOVIE' => tr('movie', lang),
      'SPECIAL' => tr('special', lang),
      'MUSIC' => tr('detail_format_music', lang),
      'TV_SHORT' => tr('detail_format_tv_short', lang),
      'MANGA' => tr('nav_manga', lang),
      'NOVEL' => tr('source_novel', lang),
      'ONE_SHOT' => tr('detail_format_one_shot', lang),
      _ => format,
    };

/// "TV · 2006": the format and start year of [media], whichever are known.
String mediaFormatAndYear(MediaRef media, String lang) => [
      if (media.format case final String format) mediaFormatLabel(format, lang),
      if (media.startYear case final int year) '$year',
    ].join(' · ');

// AniList languages with a translated name (StaffLanguage plus Chinese);
// others are shown as AniList writes them.
const _translatedLanguages = {
  'japanese',
  'english',
  'korean',
  'italian',
  'spanish',
  'portuguese',
  'french',
  'german',
  'hebrew',
  'hungarian',
  'chinese',
};

/// The name of a voice actor's [language] (AniList's English `languageV2`)
/// in the app's language.
String voiceLanguageLabel(String? language, String lang) {
  if (language == null) return '';
  final key = language.toLowerCase();
  return _translatedLanguages.contains(key) ? tr('staff_lang_$key', lang) : language;
}
