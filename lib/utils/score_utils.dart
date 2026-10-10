/// Converts a 0–10 score, as shown in the app, to AniList's 0–100 `scoreRaw`,
/// which AniList maps onto whatever score format the user has chosen.
int toRawScore(double score) => (score * 10).round().clamp(0, 100);

/// Formats a 0–10 [score] (as read with `POINT_10_DECIMAL`) in the user's
/// AniList score format, e.g. `75` for 100-point users or `4/5` for stars.
String formatScore(double score, String? format) {
  final raw = toRawScore(score);
  return switch (format) {
    'POINT_100' => '$raw',
    'POINT_10' => '${score.round()}',
    'POINT_5' => '${(raw / 20).round()}/5',
    // AniList stores the three faces as roughly 35, 60 and 85.
    'POINT_3' => raw < 48 ? '☹️' : (raw < 73 ? '😐' : '🙂'),
    _ => score.toStringAsFixed(1),
  };
}

/// The user's score format from the AniList Viewer (`mediaListOptions`).
String? scoreFormatOf(Map<String, dynamic>? viewer) =>
    (viewer?['mediaListOptions'] as Map?)?['scoreFormat'] as String?;
