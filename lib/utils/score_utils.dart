/// Converts a 0–10 score, as shown in the app, to AniList's 0–100 `scoreRaw`,
/// which AniList maps onto whatever score format the user has chosen.
int toRawScore(double score) => (score * 10).round().clamp(0, 100);
