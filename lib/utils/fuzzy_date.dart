import 'package:flutter/foundation.dart';

import 'translations.dart';

/// An AniList date where any part may be missing (its `FuzzyDate`), as used
/// for media start/end dates, list entry dates and birthdays.
@immutable
class FuzzyDate {
  const FuzzyDate({this.year, this.month, this.day});

  /// Reads AniList's `{year, month, day}`. Impossible months and days are
  /// dropped; anything else (or a date with nothing known) is [empty].
  factory FuzzyDate.fromJson(Object? json) {
    if (json is! Map) return empty;
    int? part(Object? value) => value is num ? value.toInt() : null;
    final month = part(json['month']);
    final day = part(json['day']);
    return FuzzyDate(
      year: part(json['year']),
      month: month != null && month >= 1 && month <= 12 ? month : null,
      day: day != null && day >= 1 && day <= 31 ? day : null,
    );
  }

  factory FuzzyDate.fromDateTime(DateTime date) =>
      FuzzyDate(year: date.year, month: date.month, day: date.day);

  /// Like [FuzzyDate.fromJson], but null when nothing is known, for fields
  /// where "unknown" is simply absent (e.g. a staff member's birthday).
  static FuzzyDate? maybeFromJson(Object? json) {
    final date = FuzzyDate.fromJson(json);
    return date.isEmpty ? null : date;
  }

  static const empty = FuzzyDate();

  final int? year;

  /// 1–12.
  final int? month;

  /// 1–31.
  final int? day;

  bool get isEmpty => year == null && month == null && day == null;
  bool get isNotEmpty => !isEmpty;

  /// The `FuzzyDateInput` for this date; an empty date clears it on AniList.
  Map<String, int?> toInput() => {'year': year, 'month': month, 'day': day};

  /// The same shape AniList sends, e.g. for caching.
  Map<String, int?> toJson() => toInput();

  /// The day to open a date picker on, or null without a year.
  DateTime? toDateTime() {
    final y = year;
    return y == null ? null : DateTime(y, month ?? 1, day ?? 1);
  }

  @override
  bool operator ==(Object other) =>
      other is FuzzyDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'FuzzyDate($year-$month-$day)';
}

/// [date] as "17 Jun 1961", "Jun 1961", "1961", or without the year (when
/// it's unknown or [withYear] is false) "Jun 17"; null when there's nothing
/// to show.
String? fuzzyDateLabel(FuzzyDate? date, String lang, {bool withYear = true}) {
  if (date == null) return null;
  final year = withYear ? date.year : null;
  final month = date.month;
  final day = date.day;
  final monthName = switch (month) {
    null => '',
    >= 1 && <= 12 => tr('detail_month_$month', lang),
    _ => '$month',
  };
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

/// [date] like the detail page ("9 Mar 2024", "Mar 2024" or "2024"); empty
/// without a year, as for list entry and airing dates.
String formatFuzzyDate(FuzzyDate date, String lang) =>
    date.year == null ? '' : fuzzyDateLabel(date, lang) ?? '';
