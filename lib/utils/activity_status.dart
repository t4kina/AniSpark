import 'translations.dart' show trf;

// The `status` strings AniList sends on list activities, with the key of
// their translation. Statuses that carry a progress ("watched episode 5 of")
// also have a `_progress` key whose text holds `{progress}`.
const _plainKeys = {
  'watched episode': 'activity_status_watched_episode',
  'read chapter': 'activity_status_read_chapter',
  'rewatched episode': 'activity_status_rewatched_episode',
  'reread chapter': 'activity_status_reread_chapter',
  'plans to watch': 'activity_status_plans_to_watch',
  'plans to read': 'activity_status_plans_to_read',
  'completed': 'activity_status_completed',
  'dropped': 'activity_status_dropped',
  'paused watching': 'activity_status_paused_watching',
  'paused reading': 'activity_status_paused_reading',
  'watching': 'activity_status_watching',
  'reading': 'activity_status_reading',
};

const _progressStatuses = {
  'watched episode',
  'read chapter',
  'rewatched episode',
  'reread chapter',
};

/// The translation key for an AniList activity [status], or null when the
/// status isn't one we know.
String? activityStatusKey(String status, {required bool hasProgress}) {
  final normalized = status.trim().toLowerCase();
  final key = _plainKeys[normalized];
  if (key == null) return null;
  return hasProgress && _progressStatuses.contains(normalized)
      ? '${key}_progress'
      : key;
}

/// The sentence fragment that follows the user's name, e.g. "watched
/// episode 5 of". Unknown statuses are shown as AniList sent them.
String activityStatusText(String? status, Object? progress, String lang) {
  final raw = status ?? '';
  final hasProgress = progress != null && '$progress'.isNotEmpty;
  final key = activityStatusKey(raw, hasProgress: hasProgress);
  if (key == null) {
    return hasProgress
        ? trf('feed_status_progress_of', lang, {
            'status': raw,
            'progress': progress,
          })
        : raw;
  }
  return trf(key, lang, {'progress': ?progress});
}
