/// Pure helpers for the airing calendar: grouping AniList `AiringSchedule`
/// maps (`airingAt` in epoch seconds) by the device's local calendar day.
library;

/// List statuses that count as "on my list" for the calendar filter.
const watchListStatuses = {'CURRENT', 'PLANNING'};

/// The episodes airing on one local calendar day, in airing order.
class AiringDay {
  const AiringDay({required this.date, required this.episodes});

  /// Local midnight of the day.
  final DateTime date;
  final List<Map<String, dynamic>> episodes;
}

/// Local midnight of the day [time] falls on.
DateTime localDay(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// When [schedule] airs, in local time, or null without a valid `airingAt`.
DateTime? airingTime(Map<String, dynamic> schedule) {
  final airingAt = schedule['airingAt'];
  if (airingAt is! num) return null;
  return DateTime.fromMillisecondsSinceEpoch(airingAt.toInt() * 1000);
}

/// Whole calendar days from [from]'s day to [to]'s day (0 = same day,
/// 1 = the next day), unaffected by daylight-saving shifts.
int calendarDaysBetween(DateTime from, DateTime to) {
  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);
  return end.difference(start).inDays;
}

/// `HH:mm` in 24-hour time, like the rest of the app.
String formatClock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// The user's list status for the media in [schedule] (needs
/// `media { mediaListEntry { status } }`), or null when it isn't listed.
String? listStatusOf(Map<String, dynamic> schedule) {
  final media = schedule['media'];
  final entry = media is Map ? media['mediaListEntry'] : null;
  final status = entry is Map ? entry['status'] : null;
  return status is String ? status : null;
}

/// Whether [schedule] is for something the user is watching or plans to.
bool isOnWatchList(Map<String, dynamic> schedule) =>
    watchListStatuses.contains(listStatusOf(schedule));

/// Groups [schedules] by the local day they air on, days and episodes in
/// time order. Entries without a valid `airingAt` are skipped.
List<AiringDay> groupByLocalDay(Iterable<Map<String, dynamic>> schedules) {
  // The index keeps episodes that air at the same time in their given order
  // (List.sort isn't stable).
  final timed = [
    for (final (index, schedule) in schedules.indexed)
      if (airingTime(schedule) case final time?) (time, index, schedule),
  ]..sort((a, b) {
      final byTime = a.$1.compareTo(b.$1);
      return byTime != 0 ? byTime : a.$2.compareTo(b.$2);
    });

  final days = <AiringDay>[];
  for (final (time, _, schedule) in timed) {
    final day = localDay(time);
    if (days.isNotEmpty && days.last.date == day) {
      days.last.episodes.add(schedule);
    } else {
      days.add(AiringDay(date: day, episodes: [schedule]));
    }
  }
  return [
    for (final day in days)
      AiringDay(date: day.date, episodes: List.unmodifiable(day.episodes)),
  ];
}
