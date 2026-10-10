import 'package:flutter/foundation.dart';

import '../../utils/score_utils.dart';

/// How a score format is entered: a number, stars or faces.
enum ScoreKind { number, stars, faces }

/// The user's AniList score format as the editor shows it. Scores stay on
/// the 0–10 scale everywhere else (and are saved with `toRawScore`); this
/// converts them to and from the units the user sees, e.g. `75` on the
/// 100-point scale or 4 stars.
@immutable
class ScoreScale {
  const ScoreScale._(this.format, this.kind, {required this.max, this.step = 1, this.decimals = 0});

  static const point100 = ScoreScale._('POINT_100', ScoreKind.number, max: 100);
  static const point10Decimal =
      ScoreScale._('POINT_10_DECIMAL', ScoreKind.number, max: 10, step: 0.5, decimals: 1);
  static const point10 = ScoreScale._('POINT_10', ScoreKind.number, max: 10);
  static const point5 = ScoreScale._('POINT_5', ScoreKind.stars, max: 5);
  static const point3 = ScoreScale._('POINT_3', ScoreKind.faces, max: 3);

  /// The scale of an AniList `ScoreFormat`; unknown formats use decimals,
  /// like `formatScore` does.
  static ScoreScale of(String? format) => switch (format) {
        'POINT_100' => point100,
        'POINT_10' => point10,
        'POINT_5' => point5,
        'POINT_3' => point3,
        _ => point10Decimal,
      };

  final String format;
  final ScoreKind kind;
  final int max;

  /// What the − and + buttons add.
  final num step;

  /// Decimals the user can type.
  final int decimals;

  // AniList stores the three faces as these raw (0–100) values.
  static const _faceRaw = [0, 35, 60, 85];

  /// The 0–10 [score] in this format's units, rounded like `formatScore`.
  num toUnits(double score) {
    final raw = toRawScore(score);
    return switch (format) {
      'POINT_100' => raw,
      'POINT_10' => score.round(),
      'POINT_5' => (raw / 20).round(),
      'POINT_3' => raw == 0 ? 0 : (raw < 48 ? 1 : (raw < 73 ? 2 : 3)),
      _ => raw / 10,
    };
  }

  /// The 0–10 score for [units] of this format.
  double fromUnits(num units) => switch (format) {
        'POINT_100' => units / 10,
        'POINT_10' => units.toDouble(),
        'POINT_5' => units * 2.0,
        'POINT_3' => _faceRaw[units.toInt().clamp(0, 3)] / 10,
        _ => (units * 10).round() / 10,
      };
}
