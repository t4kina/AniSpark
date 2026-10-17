/// AniList anime seasons (`MediaSeason`) and stepping between them.
library;

enum AnimeSeason {
  winter,
  spring,
  summer,
  fall;

  /// The AniList `MediaSeason` value, e.g. `FALL`.
  String get apiName => name.toUpperCase();

  /// The season named [value] (`WINTER`…`FALL`), or null if unknown.
  static AnimeSeason? fromApi(String value) {
    for (final season in values) {
      if (season.apiName == value) return season;
    }
    return null;
  }
}

/// A season of a given year, e.g. FALL 2026.
class SeasonYear {
  const SeasonYear(this.season, this.year);

  /// The season airing on [date]: Jan–Mar winter, Apr–Jun spring,
  /// Jul–Sep summer, Oct–Dec fall (AniList's convention).
  factory SeasonYear.of(DateTime date) =>
      SeasonYear(AnimeSeason.values[(date.month - 1) ~/ 3], date.year);

  /// Parses an AniList season name and year, or returns null if invalid.
  static SeasonYear? tryParse(String season, int year) {
    final parsed = AnimeSeason.fromApi(season);
    return parsed == null ? null : SeasonYear(parsed, year);
  }

  final AnimeSeason season;
  final int year;

  /// [steps] seasons later (negative for earlier), crossing years as needed.
  SeasonYear shift(int steps) {
    final index = year * 4 + season.index + steps;
    return SeasonYear(AnimeSeason.values[index % 4], index ~/ 4);
  }

  SeasonYear get next => shift(1);
  SeasonYear get previous => shift(-1);

  bool isBefore(SeasonYear other) =>
      year < other.year || (year == other.year && season.index < other.season.index);

  bool isAfter(SeasonYear other) => other.isBefore(this);

  /// Cache-key form, e.g. `FALL-2026` (same as Discover's keys).
  String get key => '${season.apiName}-$year';

  @override
  bool operator ==(Object other) =>
      other is SeasonYear && other.season == season && other.year == year;

  @override
  int get hashCode => Object.hash(season, year);

  @override
  String toString() => key;
}
