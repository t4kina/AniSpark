import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../services/discover_api.dart';
import '../utils/airing_calendar.dart';
import '../utils/translations.dart' show tr, trf;
import '../widgets/skeletons.dart';
import 'detail_screen.dart';

/// Episodes airing today and over the next six days, grouped by local day.
/// Logged-in users can narrow it to what they're watching or planning.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.api});

  /// Replaces the AniList API, for tests.
  final DiscoverApi? api;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const _days = 7;
  static const _maxAge = Duration(minutes: 30);

  static const _weekdayKeys = [
    'home_day_mon', 'home_day_tue', 'home_day_wed', 'home_day_thu',
    'home_day_fri', 'home_day_sat', 'home_day_sun',
  ];

  late final DiscoverApi _api = widget.api ?? DiscoverApi();
  List<Map<String, dynamic>>? _schedules;
  bool _loading = true;
  bool _hasError = false;
  // Null until the user picks one; "My list" is the default when logged in.
  bool? _myListOnly;
  // Ignores responses from loads that a newer one replaced.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Shows the cached calendar right away and refreshes it once it's older
  /// than [_maxAge] (or always when [force]).
  Future<void> _load({bool force = false}) async {
    final auth = context.read<AuthService>();
    final token = auth.token;
    final userId = auth.user?['id'] as int?;
    final cache = context.read<ApiCache>();
    final today = localDay(DateTime.now());
    final end = DateTime(today.year, today.month, today.day + _days);
    final request = ++_request;
    if (_hasError) {
      setState(() {
        _hasError = false;
        _loading = _schedules == null;
      });
    }

    void show(List<Map<String, dynamic>> schedules, {required bool isFresh}) {
      if (!mounted || request != _request) return;
      setState(() {
        _schedules = schedules;
        _loading = false;
      });
    }

    Future<List<Map<String, dynamic>>> fetch() =>
        _api.airingSchedule(from: today, to: end, token: token);

    // A new day gets a new key, so the calendar never starts on yesterday.
    final name = 'calendar:${_dateKey(today)}';
    // With a token the data carries the user's list statuses.
    final key = switch ((token, userId)) {
      (null, _) => name,
      (_, final int id) => ApiCache.userKey(id, name),
      _ => null, // Account id not fetched yet: no cache namespace for it.
    };

    try {
      if (key == null) {
        show(await fetch(), isFresh: true);
        return;
      }
      await cache.load<List<Map<String, dynamic>>>(
        key: key,
        fetch: fetch,
        decode: _decode,
        onData: show,
        maxAge: _maxAge,
        force: force,
      );
    } on Exception catch (e) {
      debugPrint('[CalendarScreen] Loading the airing calendar failed: $e');
      if (!mounted || request != _request) return;
      final hasData = _schedules != null;
      setState(() {
        _loading = false;
        _hasError = !hasData;
      });
      if (force && hasData) _showLoadError();
    }
  }

  void _showLoadError() {
    final lang = context.read<SettingsProvider>().language;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('load_error', lang))));
  }

  static List<Map<String, dynamic>> _decode(Object? json) => List.unmodifiable(
      [for (final item in json as List) item as Map<String, dynamic>]);

  static String _dateKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final loggedIn = context.select<AuthService, bool>((a) => a.isLoggedIn);
    final myListOnly = loggedIn && (_myListOnly ?? true);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('cal_title', lang),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          if (loggedIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.public, size: 18),
                      label: Text(tr('cal_filter_all', lang)),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.bookmark_outline, size: 18),
                      label: Text(tr('cal_filter_my_list', lang)),
                    ),
                  ],
                  selected: {myListOnly},
                  onSelectionChanged: (selection) =>
                      setState(() => _myListOnly = selection.first),
                ),
              ),
            ),
          Expanded(child: _buildContent(lang, myListOnly: myListOnly)),
        ],
      ),
    );
  }

  Widget _buildContent(String lang, {required bool myListOnly}) {
    if (_loading) return const _CalendarSkeleton();
    if (_hasError) return _buildError(lang);
    final now = DateTime.now();
    final today = localDay(now);
    final days = groupByLocalDay([
      for (final schedule in _schedules ?? const <Map<String, dynamic>>[])
        if (!myListOnly || isOnWatchList(schedule)) schedule,
    ]).where((day) => !day.date.isBefore(today)).toList();

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: days.isEmpty
          ? _buildEmpty(lang, myListOnly: myListOnly)
          : CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                for (final day in days)
                  SliverMainAxisGroup(
                    slivers: [
                      PinnedHeaderSliver(
                        child: _DayHeader(
                          label: _dayLabel(day.date, today, lang),
                          date: trf('cal_month_day', lang, {
                            'month': tr('detail_month_${day.date.month}', lang),
                            'day': day.date.day,
                          }),
                        ),
                      ),
                      SliverList.builder(
                        itemCount: day.episodes.length,
                        itemBuilder: (_, i) => _EpisodeRow(
                          schedule: day.episodes[i],
                          now: now,
                          lang: lang,
                        ),
                      ),
                    ],
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
    );
  }

  String _dayLabel(DateTime day, DateTime today, String lang) =>
      switch (calendarDaysBetween(today, day)) {
        0 => tr('cal_today', lang),
        1 => tr('cal_tomorrow', lang),
        _ => tr(_weekdayKeys[day.weekday - 1], lang),
      };

  Widget _buildEmpty(String lang, {required bool myListOnly}) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
        children: [
          const Icon(Icons.event_busy_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            tr(myListOnly ? 'cal_empty_my_list' : 'cal_empty_all', lang),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          if (myListOnly) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => setState(() => _myListOnly = false),
                child: Text(tr('cal_show_all', lang)),
              ),
            ),
          ],
        ],
      );

  Widget _buildError(String lang) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(tr('load_error', lang), style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(tr('retry', lang)),
            ),
          ],
        ),
      );
}

/// Sticky "Today · Oct 10" header above one day's episodes.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.date});

  final String label;
  final String date;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Container(
          width: double.infinity,
          color: Theme.of(context).scaffoldBackgroundColor,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(date, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      );
}

/// One airing episode: cover, title, episode number, list badge and time.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.schedule, required this.now, required this.lang});

  final Map<String, dynamic> schedule;
  final DateTime now;
  final String lang;

  /// Label keys of the user's AniList list statuses.
  static const _statusKeys = {
    'CURRENT': 'watching',
    'PLANNING': 'plan_to_watch',
    'COMPLETED': 'completed',
    'PAUSED': 'on_hold',
    'DROPPED': 'dropped',
    'REPEATING': 'rewatching',
  };

  @override
  Widget build(BuildContext context) {
    final media = schedule['media'] as Map<String, dynamic>? ?? const {};
    final id = media['id'] as int?;
    final cover = (media['coverImage'] as Map?)?['large'] as String?;
    final title = context
        .read<SettingsProvider>()
        .resolveTitle(media['title'] as Map<String, dynamic>?);
    final episode = (schedule['episode'] as num?)?.toInt();
    final time = airingTime(schedule);
    final aired = time != null && !time.isAfter(now);
    final statusKey = _statusKeys[listStatusOf(schedule)];
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(color: cs.surfaceContainerHighest);

    return InkWell(
      onTap: id == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DetailScreen(animeId: id)),
              ),
      child: Opacity(
        opacity: aired ? 0.6 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 46,
                  height: 64,
                  child: cover == null
                      ? placeholder
                      : CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          memCacheWidth: 92,
                          placeholder: (_, _) => placeholder,
                          errorWidget: (_, _, _) => placeholder,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (episode != null)
                          Text(
                            trf('list_episode_n', lang, {'n': episode}),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        if (statusKey != null) _ListBadge(label: tr(statusKey, lang)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (time != null)
                    Text(
                      formatClock(time),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: aired ? Colors.grey : cs.primary,
                      ),
                    ),
                  if (aired)
                    Text(
                      tr('cal_aired', lang),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small tinted pill with the user's list status.
class _ListBadge extends StatelessWidget {
  const _ListBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Placeholder shaped like two days of calendar rows.
class _CalendarSkeleton extends StatelessWidget {
  const _CalendarSkeleton();

  @override
  Widget build(BuildContext context) => Skeleton(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 8),
          children: [
            for (var day = 0; day < 2; day++) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonBox(width: 120, height: 15),
                ),
              ),
              for (var row = 0; row < 4; row++)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      SkeletonBox(width: 46, height: 64),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(height: 13),
                            SizedBox(height: 8),
                            SkeletonBox(width: 90, height: 11),
                          ],
                        ),
                      ),
                      SizedBox(width: 12),
                      SkeletonBox(width: 40, height: 13),
                    ],
                  ),
                ),
            ],
          ],
        ),
      );
}
