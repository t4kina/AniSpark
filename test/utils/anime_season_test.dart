import 'package:anispark/utils/anime_season.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SeasonYear.of follows AniList quarters', () {
    expect(SeasonYear.of(DateTime(2026, 1, 1)), const SeasonYear(AnimeSeason.winter, 2026));
    expect(SeasonYear.of(DateTime(2026, 3, 31)), const SeasonYear(AnimeSeason.winter, 2026));
    expect(SeasonYear.of(DateTime(2026, 4, 1)), const SeasonYear(AnimeSeason.spring, 2026));
    expect(SeasonYear.of(DateTime(2026, 8, 15)), const SeasonYear(AnimeSeason.summer, 2026));
    expect(SeasonYear.of(DateTime(2026, 10, 10)), const SeasonYear(AnimeSeason.fall, 2026));
    expect(SeasonYear.of(DateTime(2026, 12, 31)), const SeasonYear(AnimeSeason.fall, 2026));
  });

  test('next and previous cross years', () {
    const fall = SeasonYear(AnimeSeason.fall, 2026);
    const winter = SeasonYear(AnimeSeason.winter, 2027);

    expect(fall.next, winter);
    expect(winter.previous, fall);
    expect(winter.shift(-5), const SeasonYear(AnimeSeason.fall, 2025));
    expect(fall.shift(6), const SeasonYear(AnimeSeason.spring, 2028));
    expect(fall.shift(0), fall);
  });

  test('tryParse reads AniList season names', () {
    expect(SeasonYear.tryParse('SPRING', 2025), const SeasonYear(AnimeSeason.spring, 2025));
    expect(SeasonYear.tryParse('spring', 2025), isNull);
    expect(SeasonYear.tryParse('AUTUMN', 2025), isNull);
  });

  test('key and apiName match the cache keys used by Discover', () {
    expect(const SeasonYear(AnimeSeason.fall, 2026).key, 'FALL-2026');
    expect(AnimeSeason.values.map((s) => s.apiName), ['WINTER', 'SPRING', 'SUMMER', 'FALL']);
  });

  test('compares chronologically', () {
    const a = SeasonYear(AnimeSeason.fall, 2025);
    const b = SeasonYear(AnimeSeason.winter, 2026);

    expect(a.isBefore(b), isTrue);
    expect(b.isAfter(a), isTrue);
    expect(a.isBefore(a), isFalse);
    expect(a.isAfter(a), isFalse);
  });
}
