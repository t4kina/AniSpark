import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show MissingPluginException, PlatformException;
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../services/device_calendar.dart';
import '../services/discover_api.dart';
import '../theme/app_motion.dart';
import '../utils/airing_calendar.dart';
import '../utils/airing_event.dart';
import '../utils/haptics.dart';
import '../utils/translations.dart' show tr, trf;
import '../widgets/motion/cover_hero.dart';
import '../widgets/motion/fade_switcher.dart';
import '../widgets/motion/pressable.dart';
import '../widgets/motion/rounded_hero.dart';
import '../widgets/motion/staggered_entrance.dart';
import '../widgets/skeletons.dart';
import 'detail_screen.dart';

/// Episodes airing today and over the next six days, grouped by local day.
/// Logged-in users can narrow it to what they're watching or planning, and
/// swipe an upcoming episode left to add it to the device's calendar.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.api, this.addCalendarEvent});

  /// Replaces the AniList API, for tests.
  final DiscoverApi? api;

  /// Replaces the platform's "new event" sheet, for tests.
  final AddCalendarEvent? addCalendarEvent;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
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
  // Who the shown data was loaded for, to reload when the session changes.
  (String?, int?)? _session;
  // A "new event" sheet is open; iOS can only show one.
  bool _addingEvent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthService>();
    final session = (auth.token, auth.user?['id'] as int?);
    final previous = _session;
    _session = session;
    if (previous == null || previous == session) return;
    // The list statuses belong to the previous session: don't show them
    // while the new ones load (build runs right after this).
    _schedules = null;
    _loading = true;
    _hasError = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  /// Shows the cached calendar right away and refreshes it once it's older
  /// than [_maxAge] (or always when [force]).
  Future<void> _load({bool force = false}) async {
    final auth = context.read<AuthService>();
    final token = auth.token;
    final userId = auth.user?['id'] as int?;
    final cache = context.read<ApiCache>();
    final today = localDay(DateTime.now());
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
        _api.weekSchedule(token: token);

    // A new day gets a new key, so the calendar never starts on yesterday.
    final name = DiscoverApi.weekCacheName(today);
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
        decode: DiscoverApi.decodeSchedule,
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

  /// Opens the calendar's "new event" sheet for an upcoming episode, filled
  /// in with the show, episode, airing time and length.
  Future<void> _addToCalendar(Map<String, dynamic> schedule, String title) async {
    if (_addingEvent) return;
    final lang = context.read<SettingsProvider>().language;
    final episode = (schedule['episode'] as num?)?.toInt();
    final event = airingEvent(
      schedule,
      title: title,
      episodeLabel: episode == null ? null : trf('list_episode_n', lang, {'n': episode}),
    );
    if (event == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final addEvent = widget.addCalendarEvent ?? openNewCalendarEvent;
    _addingEvent = true;
    bool? done;
    try {
      done = await addEvent(event);
    } on PlatformException catch (e) {
      debugPrint('[CalendarScreen] Opening the calendar failed: $e');
    } on MissingPluginException catch (e) {
      debugPrint('[CalendarScreen] Opening the calendar failed: $e');
    } finally {
      _addingEvent = false;
    }
    // iOS reports whether the event was saved (false: cancelled), Android
    // only whether a calendar app opened.
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final message = switch (done) {
      null => 'cal_open_failed',
      true when ios => 'cal_event_added',
      false when !ios => 'cal_open_failed',
      _ => null,
    };
    if (message == null) return;
    messenger.showSnackBar(SnackBar(content: Text(tr(message, lang))));
  }

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

  /// The calendar cascades in when it loads (the gate only restarts on new
  /// data), and switching between "All" and "My list" cross-fades.
  Widget _buildContent(String lang, {required bool myListOnly}) => EntranceGate(
        trigger: _schedules,
        child: FadeSwitcher(child: _buildState(lang, myListOnly: myListOnly)),
      );

  Widget _buildState(String lang, {required bool myListOnly}) {
    if (_loading) return const _CalendarSkeleton();
    if (_hasError) return _buildError(lang);
    final now = DateTime.now();
    final today = localDay(now);
    final days = groupByLocalDay([
      for (final schedule in _schedules ?? const <Map<String, dynamic>>[])
        if (!myListOnly || isOnWatchList(schedule)) schedule,
    ]).where((day) => !day.date.isBefore(today)).toList();
    // Both filters' lists are on screen while they cross-fade, so their
    // covers need different hero tags.
    final heroScope = myListOnly ? 'calendar-mine' : 'calendar-all';

    // Position of each day's header in the whole list, for the cascade.
    final firstIndexOfDay = <int>[];
    var next = 0;
    for (final day in days) {
      firstIndexOfDay.add(next);
      next += 1 + day.episodes.length;
    }

    return RefreshIndicator(
      key: ValueKey(heroScope),
      onRefresh: () => _load(force: true),
      child: days.isEmpty
          ? _buildEmpty(lang, myListOnly: myListOnly)
          : CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                for (final (d, day) in days.indexed)
                  SliverMainAxisGroup(
                    slivers: [
                      PinnedHeaderSliver(
                        child: StaggeredEntrance(
                          index: firstIndexOfDay[d],
                          child: _DayHeader(
                            label: _dayLabel(day.date, today, lang),
                            date: trf('cal_month_day', lang, {
                              'month': tr('detail_month_${day.date.month}', lang),
                              'day': day.date.day,
                            }),
                          ),
                        ),
                      ),
                      SliverList.builder(
                        itemCount: day.episodes.length,
                        itemBuilder: (_, i) => StaggeredEntrance(
                          index: firstIndexOfDay[d] + 1 + i,
                          child: _EpisodeRow(
                            schedule: day.episodes[i],
                            now: now,
                            lang: lang,
                            heroScope: heroScope,
                            onAddToCalendar: (title) => _addToCalendar(day.episodes[i], title),
                          ),
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
/// Until it airs, swiping it left adds it to the calendar.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.schedule,
    required this.now,
    required this.lang,
    required this.heroScope,
    required this.onAddToCalendar,
  });

  final Map<String, dynamic> schedule;
  final DateTime now;
  final String lang;

  /// The list's scope for the cover's hero tag.
  final String heroScope;

  /// Called with the show's title when the row is swiped left.
  final ValueChanged<String> onAddToCalendar;

  /// How visible episodes that already aired are.
  static const _airedOpacity = 0.6;

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
    // The cover is dimmed by its own paint rather than an Opacity around
    // the row, so it stays dimmed while it flies to the detail page.
    final dim = aired ? Colors.white.withValues(alpha: _airedOpacity) : null;
    final placeholder = ColoredBox(
      color: cs.surfaceContainerHighest.withValues(alpha: aired ? _airedOpacity : 1),
    );
    // A show can air more than once in the week shown.
    final airingId = schedule['id'] ?? schedule['airingAt'];
    final heroTag = id == null ? null : coverHeroTag('$heroScope-$airingId', id);

    final row = Pressable(
      // A full-width row only needs a hint of a press.
      pressedScale: 0.98,
      onTap: id == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetailScreen(animeId: id, heroTag: heroTag, initialCoverUrl: cover),
                ),
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              height: 64,
              child: RoundedHero(
                tag: heroTag,
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                child: cover == null
                    ? placeholder
                    : CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        memCacheWidth: 92,
                        color: dim,
                        colorBlendMode: dim == null ? null : BlendMode.modulate,
                        fadeInDuration: AppMotion.of(context, AppMotion.short),
                        fadeOutDuration: Duration.zero,
                        placeholder: (_, _) => placeholder,
                        errorWidget: (_, _, _) => placeholder,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: aired ? _airedOpacity : 1,
                child: Row(
                  children: [
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
          ],
        ),
      ),
    );
    if (time == null || aired) return row;
    return _AddToCalendarSwipe(
      id: '$heroScope-$airingId',
      label: tr('cal_add_event', lang),
      onAdd: () => onAddToCalendar(title),
      child: row,
    );
  }
}

/// Swiping [child] to the left calls [onAdd], which opens the calendar's
/// "new event" sheet; the row springs back rather than leaving the list.
class _AddToCalendarSwipe extends StatefulWidget {
  const _AddToCalendarSwipe({
    required this.id,
    required this.label,
    required this.onAdd,
    required this.child,
  });

  /// Unique among the rows, for the [Dismissible].
  final String id;
  final String label;
  final VoidCallback onAdd;
  final Widget child;

  @override
  State<_AddToCalendarSwipe> createState() => _AddToCalendarSwipeState();
}

class _AddToCalendarSwipeState extends State<_AddToCalendarSwipe> {
  /// How far (of the row's width) a swipe goes before letting go adds it.
  static const _threshold = 0.3;

  /// Dragged past [_threshold], so letting go adds the event.
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      customSemanticsActions: {CustomSemanticsAction(label: widget.label): widget.onAdd},
      child: Dismissible(
        key: ValueKey(widget.id),
        direction: DismissDirection.endToStart,
        dismissThresholds: const {DismissDirection.endToStart: _threshold},
        onUpdate: (details) {
          if (details.reached == _armed) return;
          setState(() => _armed = details.reached);
          if (_armed) selectionHaptic();
        },
        confirmDismiss: (_) async {
          widget.onAdd();
          return false;
        },
        background: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary.withValues(alpha: 0), cs.primary.withValues(alpha: 0.9)],
              stops: const [0.2, 1],
            ),
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  AnimatedScale(
                    scale: _armed ? 1.2 : 1,
                    duration: AppMotion.of(context, AppMotion.short),
                    curve: AppMotion.standard,
                    child: Icon(Icons.edit_calendar_rounded, color: cs.onPrimary, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),
        child: widget.child,
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
