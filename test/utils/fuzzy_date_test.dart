import 'package:anispark/utils/fuzzy_date.dart';
import 'package:anispark/utils/translations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FuzzyDate', () {
    test('reads the parts AniList knows', () {
      expect(FuzzyDate.fromJson({'year': 2024, 'month': 3, 'day': 9}), const FuzzyDate(year: 2024, month: 3, day: 9));
      expect(FuzzyDate.fromJson({'year': 2024}), const FuzzyDate(year: 2024));
      expect(FuzzyDate.fromJson({'year': 2024.0, 'month': 3.0}), const FuzzyDate(year: 2024, month: 3));
    });

    test('is empty when nothing is known or the shape is wrong', () {
      expect(FuzzyDate.fromJson({'year': null, 'month': null, 'day': null}).isEmpty, isTrue);
      expect(FuzzyDate.fromJson(null).isEmpty, isTrue);
      expect(FuzzyDate.fromJson('2000-01-01').isEmpty, isTrue);
      expect(FuzzyDate.fromJson({'year': 2024}).isNotEmpty, isTrue);
    });

    test('drops impossible months and days', () {
      expect(FuzzyDate.fromJson({'year': 2000, 'month': 13, 'day': 0}), const FuzzyDate(year: 2000));
      expect(FuzzyDate.fromJson({'month': 0}).isEmpty, isTrue);
    });

    test('maybeFromJson is null when nothing is known', () {
      expect(FuzzyDate.maybeFromJson({'month': 0}), isNull);
      expect(FuzzyDate.maybeFromJson(null), isNull);
      expect(FuzzyDate.maybeFromJson({'month': 6, 'day': 17}), const FuzzyDate(month: 6, day: 17));
    });

    test('writes AniList input, where an empty date clears it, and survives a JSON round trip', () {
      expect(FuzzyDate.empty.toInput(), {'year': null, 'month': null, 'day': null});
      expect(const FuzzyDate(year: 2024).toInput(), {'year': 2024, 'month': null, 'day': null});
      const date = FuzzyDate(year: 1961, month: 6, day: 17);
      expect(FuzzyDate.fromJson(date.toJson()), date);
    });

    test('converts to and from a picker date', () {
      expect(FuzzyDate.fromDateTime(DateTime(2026, 10, 12)), const FuzzyDate(year: 2026, month: 10, day: 12));
      expect(const FuzzyDate(year: 2024).toDateTime(), DateTime(2024));
      expect(const FuzzyDate(year: 2024, month: 3, day: 9).toDateTime(), DateTime(2024, 3, 9));
      expect(FuzzyDate.empty.toDateTime(), isNull);
    });

    test('compares by value', () {
      expect(const FuzzyDate(year: 2024, month: 3), const FuzzyDate(year: 2024, month: 3));
      expect(const FuzzyDate(year: 2024, month: 3).hashCode, const FuzzyDate(year: 2024, month: 3).hashCode);
      expect(const FuzzyDate(year: 2024, month: 3), isNot(const FuzzyDate(year: 2024)));
    });
  });

  group('fuzzyDateLabel', () {
    test('shows whatever part of the date is known', () {
      const full = FuzzyDate(year: 1961, month: 6, day: 17);
      expect(fuzzyDateLabel(full, 'English'), '17 Jun 1961');
      expect(fuzzyDateLabel(full, 'English', withYear: false), 'Jun 17');
      expect(fuzzyDateLabel(const FuzzyDate(year: 1961, month: 6), 'English'), 'Jun 1961');
      expect(fuzzyDateLabel(const FuzzyDate(year: 1961), 'English'), '1961');
      expect(fuzzyDateLabel(const FuzzyDate(year: 1961), 'English', withYear: false), isNull);
      expect(fuzzyDateLabel(const FuzzyDate(day: 5), 'English'), '5');
      expect(fuzzyDateLabel(FuzzyDate.empty, 'English'), isNull);
      expect(fuzzyDateLabel(null, 'English'), isNull);
    });

    test('uses the translated month names', () {
      expect(fuzzyDateLabel(const FuzzyDate(year: 2024, month: 3), 'Spanish'),
          trf('detail_date_month_year', 'Spanish', {'month': tr('detail_month_3', 'Spanish'), 'year': 2024}));
    });
  });

  group('formatFuzzyDate', () {
    test('formats dates that have a year like the detail page', () {
      expect(formatFuzzyDate(const FuzzyDate(year: 2024, month: 3, day: 9), 'English'), '9 Mar 2024');
      expect(formatFuzzyDate(const FuzzyDate(year: 2024, month: 3), 'English'), 'Mar 2024');
      expect(formatFuzzyDate(const FuzzyDate(year: 2024), 'English'), '2024');
    });

    test('is empty without a year', () {
      expect(formatFuzzyDate(const FuzzyDate(month: 3, day: 9), 'English'), '');
      expect(formatFuzzyDate(FuzzyDate.empty, 'English'), '');
    });
  });
}
