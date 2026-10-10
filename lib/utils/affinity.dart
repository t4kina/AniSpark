import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

// Affinity between two users' anime (or manga) lists.
//
// Affinity is the Pearson correlation coefficient r of the two users' scores
// on the titles both of them have scored, shown as r × 100 (−100% … 100%),
// the way MyAnimeList's affinity and the AniList affinity tools show it:
// around 0% means unrelated tastes and a negative value opposite ones.
// Pearson's r ignores each user's offset and spread, so a harsh scorer and a
// generous one who rank titles the same way still get 100%. Scores are read
// on AniList's 0–100 scale (`score(format: POINT_100)`) so lists kept in
// different score formats (10-point, 5 stars, 3 smileys…) compare.

/// Titles both users must have scored before an affinity is shown. With
/// fewer, a single score swings the percentage wildly.
const minScoredInCommon = 10;

/// One title on a user's list. [score] is on AniList's 0–100 scale and 0
/// when unscored; [title] and [coverUrl] are only needed for display.
@immutable
class AffinityEntry {
  const AffinityEntry({
    required this.mediaId,
    required this.score,
    this.status,
    this.title,
    this.coverUrl,
  });

  final int mediaId;
  final double score;

  /// AniList's `MediaListStatus` (`COMPLETED`, `CURRENT`, …).
  final String? status;

  /// `{romaji, english, native}`.
  final Map<String, dynamic>? title;
  final String? coverUrl;

  bool get isScored => _isScore(score);
}

/// A title on both users' lists, with both scores (0 when unscored) and
/// statuses. Title and cover come from the viewer's ("my") list.
@immutable
class SharedTitle {
  const SharedTitle({
    required this.mediaId,
    required this.myScore,
    required this.theirScore,
    this.myStatus,
    this.theirStatus,
    this.title,
    this.coverUrl,
  });

  final int mediaId;
  final double myScore;
  final double theirScore;
  final String? myStatus;
  final String? theirStatus;
  final Map<String, dynamic>? title;
  final String? coverUrl;

  bool get bothScored => _isScore(myScore) && _isScore(theirScore);

  /// How far apart the two scores are (0–100), or null unless both scored.
  double? get gap => bothScored ? (myScore - theirScore).abs() : null;

  Map<String, dynamic> toJson() => {
        'id': mediaId,
        'm': myScore,
        't': theirScore,
        'ms': ?myStatus,
        'ts': ?theirStatus,
        'ti': ?title,
        'c': ?coverUrl,
      };

  /// Parses one [toJson] map; null when it has no media id.
  static SharedTitle? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! int) return null;
    final title = json['ti'];
    return SharedTitle(
      mediaId: id,
      myScore: _scoreFrom(json['m']),
      theirScore: _scoreFrom(json['t']),
      myStatus: _stringFrom(json['ms']),
      theirStatus: _stringFrom(json['ts']),
      title: title is Map ? title.cast<String, dynamic>() : null,
      coverUrl: _stringFrom(json['c']),
    );
  }

  /// Parses a cached list, skipping malformed entries. Throws a
  /// [FormatException] for anything but a list so the cache treats it as a
  /// miss.
  static List<SharedTitle> listFromJson(Object? json) {
    if (json is! List) throw const FormatException('Cached shared titles are not a list');
    return List.unmodifiable([for (final item in json) ?fromJson(item)]);
  }
}

/// Why an [Affinity] has, or hasn't, a percentage.
enum AffinityOutcome {
  computed,

  /// Fewer than the minimum titles were scored by both.
  notEnoughTitles,

  /// One of them gave every shared title the same score, so there is no
  /// ranking to correlate.
  uniformScores,
}

/// How similar two tastes are, banded from the percentage.
enum AffinityTier { strong, moderate, weak, opposite }

/// The band of an affinity [percent]: 60%+ strong, 30%+ moderate, 0%+ weak,
/// below 0% opposite.
AffinityTier tierOf(int percent) => switch (percent) {
      >= 60 => AffinityTier.strong,
      >= 30 => AffinityTier.moderate,
      >= 0 => AffinityTier.weak,
      _ => AffinityTier.opposite,
    };

/// The affinity between the viewer and another user over their [shared]
/// titles, plus the summaries the compare screen shows.
@immutable
class Affinity {
  const Affinity._({
    required this.shared,
    required this.scoredInCommon,
    required this.outcome,
    this.correlation,
    this.myMean,
    this.theirMean,
    required this.completedOnlyByMe,
    required this.completedOnlyByThem,
  });

  /// Computes the affinity over [shared], requiring [minScored] titles
  /// scored by both.
  factory Affinity.of(List<SharedTitle> shared, {int minScored = minScoredInCommon}) {
    final pairs = [for (final title in shared) if (title.bothScored) title];
    final mine = [for (final title in pairs) title.myScore];
    final theirs = [for (final title in pairs) title.theirScore];
    final correlation = pairs.length >= minScored ? pearson(mine, theirs) : null;
    final outcome = pairs.length < minScored
        ? AffinityOutcome.notEnoughTitles
        : (correlation == null ? AffinityOutcome.uniformScores : AffinityOutcome.computed);
    return Affinity._(
      shared: List.unmodifiable(shared),
      scoredInCommon: pairs.length,
      outcome: outcome,
      correlation: correlation,
      myMean: _mean(mine),
      theirMean: _mean(theirs),
      completedOnlyByMe: shared
          .where((t) => _isCompleted(t.myStatus) && !_isCompleted(t.theirStatus))
          .length,
      completedOnlyByThem: shared
          .where((t) => _isCompleted(t.theirStatus) && !_isCompleted(t.myStatus))
          .length,
    );
  }

  /// Titles on both lists.
  final List<SharedTitle> shared;

  /// Shared titles both users scored; the affinity is computed over these.
  final int scoredInCommon;
  final AffinityOutcome outcome;

  /// Pearson's r in [-1, 1], or null when [outcome] isn't computed.
  final double? correlation;

  /// Each user's mean score (0–100) over the titles both scored.
  final double? myMean;
  final double? theirMean;

  /// Shared titles one user has completed (or is rewatching) and the other
  /// hasn't.
  final int completedOnlyByMe;
  final int completedOnlyByThem;

  /// The affinity as a rounded percentage (−100 … 100), or null.
  int? get percent => switch (correlation) {
        final r? => (r * 100).round(),
        null => null,
      };

  AffinityTier? get tier => switch (percent) {
        final p? => tierOf(p),
        null => null,
      };
}

/// The titles on both lists, in the order of [mine]. MediaListCollection
/// repeats an entry in every custom list it belongs to, so each media
/// counts once.
List<SharedTitle> sharedTitles(Iterable<AffinityEntry> mine, Iterable<AffinityEntry> theirs) {
  final theirsById = uniqueEntries(theirs);
  return List.unmodifiable([
    for (final own in uniqueEntries(mine).values)
      if (theirsById[own.mediaId] case final other?)
        SharedTitle(
          mediaId: own.mediaId,
          myScore: own.score,
          theirScore: other.score,
          myStatus: own.status,
          theirStatus: other.status,
          title: own.title,
          coverUrl: own.coverUrl,
        ),
  ]);
}

/// [entries] by media id, once each, keeping the first copy unless a later
/// one carries a score the first lacks.
Map<int, AffinityEntry> uniqueEntries(Iterable<AffinityEntry> entries) {
  final byId = <int, AffinityEntry>{};
  for (final entry in entries) {
    final existing = byId[entry.mediaId];
    if (existing == null || (!existing.isScored && entry.isScored)) {
      byId[entry.mediaId] = entry;
    }
  }
  return byId;
}

/// Pearson's correlation coefficient of the paired samples [xs] and [ys],
/// or null when it is undefined: fewer than two pairs, lists of different
/// lengths, or a side whose values are all equal (zero variance).
double? pearson(List<double> xs, List<double> ys) {
  final n = xs.length;
  if (n < 2 || ys.length != n || _isConstant(xs) || _isConstant(ys)) return null;
  final meanX = _mean(xs)!;
  final meanY = _mean(ys)!;
  var sumXY = 0.0;
  var sumXX = 0.0;
  var sumYY = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - meanX;
    final dy = ys[i] - meanY;
    sumXY += dx * dy;
    sumXX += dx * dx;
    sumYY += dy * dy;
  }
  if (sumXX <= 0 || sumYY <= 0) return null;
  final r = sumXY / math.sqrt(sumXX * sumYY);
  return r.isFinite ? r.clamp(-1.0, 1.0) : null;
}

/// How the compare screen orders shared titles.
enum CompareSort { agreement, disagreement, title }

/// [shared] ordered by [sort], as a new list. Titles not scored by both
/// always go last (by title); ties go to the titles the two rate higher
/// together, then by title. [titleOf] gives the displayed title.
List<SharedTitle> sortShared(
  Iterable<SharedTitle> shared,
  CompareSort sort,
  String Function(SharedTitle title) titleOf,
) {
  // Each displayed title is resolved and lower-cased once, not per comparison.
  final keyed = <_Named>[
    for (final title in shared) (title: title, name: titleOf(title).toLowerCase()),
  ];

  int compare(_Named a, _Named b) {
    final byName = a.name.compareTo(b.name);
    if (sort == CompareSort.title) return byName;
    final gapA = a.title.gap;
    final gapB = b.title.gap;
    if (gapA == null || gapB == null) {
      if (gapA != null) return -1;
      if (gapB != null) return 1;
      return byName;
    }
    final byGap = sort == CompareSort.agreement ? gapA.compareTo(gapB) : gapB.compareTo(gapA);
    if (byGap != 0) return byGap;
    final byCombined = (b.title.myScore + b.title.theirScore)
        .compareTo(a.title.myScore + a.title.theirScore);
    return byCombined != 0 ? byCombined : byName;
  }

  keyed.sort(compare);
  return [for (final item in keyed) item.title];
}

typedef _Named = ({SharedTitle title, String name});

bool _isScore(double score) => score > 0 && score.isFinite;

bool _isCompleted(String? status) => status == 'COMPLETED' || status == 'REPEATING';

bool _isConstant(List<double> values) => values.every((value) => value == values.first);

double? _mean(List<double> values) =>
    values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

double _scoreFrom(Object? value) =>
    value is num && value.isFinite ? value.toDouble().clamp(0.0, 100.0) : 0.0;

String? _stringFrom(Object? value) => value is String ? value : null;
