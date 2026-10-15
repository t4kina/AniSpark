import '../services/device_calendar.dart';
import 'airing_calendar.dart';

/// How long an episode lasts when AniList doesn't say.
const defaultEpisodeLength = Duration(minutes: 24);

/// A calendar event for watching an airing episode. [schedule] is an AniList
/// `AiringSchedule` with its media, [title] the show's title as the user
/// reads it and [episodeLabel] e.g. "Episode 3". Null without an airing time.
CalendarEvent? airingEvent(Map<String, dynamic> schedule, {required String title, String? episodeLabel}) {
  final start = airingTime(schedule);
  if (start == null) return null;
  final media = schedule['media'] as Map<String, dynamic>? ?? const {};
  final minutes = (media['duration'] as num?)?.toInt() ?? 0;
  final id = media['id'];
  final url = id is int ? 'https://anilist.co/anime/$id' : null;
  return CalendarEvent(
    title: episodeLabel == null ? title : '$title · $episodeLabel',
    start: start,
    end: start.add(minutes > 0 ? Duration(minutes: minutes) : defaultEpisodeLength),
    notes: url,
    url: url,
    alertAtStart: true,
  );
}
