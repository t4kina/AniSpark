import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../services/anilist_service.dart';
import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../services/browse_api.dart';
import '../services/discover_api.dart';
import '../providers/settings_provider.dart';
import '../theme/app_motion.dart';
import '../utils/anime_season.dart';
import '../utils/tab_reselect.dart';
import '../utils/translations.dart' show tr, trf;
import '../widgets/anime_card.dart';
import '../widgets/motion/cover_hero.dart';
import '../widgets/motion/fade_switcher.dart';
import '../widgets/motion/pressable.dart';
import '../widgets/motion/rounded_hero.dart';
import 'browse_screen.dart';
import 'calendar_screen.dart';
import 'detail_screen.dart';
import 'search_screen.dart';
import 'season_screen.dart';

/// The bottom-navigation tab that shows Discover.
const _discoverTab = 2;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.discover});

  /// Replaces the AniList discover API, for tests.
  final DiscoverApi? discover;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = AniListService();
  late final DiscoverApi _discover = widget.discover ?? DiscoverApi();
  final _scroll = ScrollController();
  late final VoidCallback _stopListeningToReselect;
  List<dynamic> _trending = [];
  List<dynamic> _seasonal = [];
  List<dynamic> _popular = [];
  List<dynamic> _topAiring = [];
  List<dynamic> _trendingManga = [];
  List<dynamic> _topManga = [];
  List<dynamic> _manhwa = [];
  List<dynamic> _weeklySchedule = [];
  bool _loading = true;
  bool _hasError = false;

  static const _sectionMaxAge = Duration(hours: 1);
  static const _scheduleMaxAge = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    _stopListeningToReselect = scrollToTopOnReselect(
      tabReselectedNotifier,
      tab: _discoverTab,
      onReselected: _scrollToTop,
    );
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCalendar());
  }

  @override
  void dispose() {
    _stopListeningToReselect();
    _scroll.dispose();
    super.dispose();
  }

  /// Tapping Discover again while it's open goes back to the top.
  void _scrollToTop() {
    if (!mounted) return;
    scrollToTop(_scroll, animate: !AppMotion.reduced(context));
  }

  Future<void> _refresh() async {
    await Future.wait([_load(force: true), _loadCalendar(force: true)]);
  }

  /// THIS WEEK is the calendar's week (same fetch, same cache entry, so
  /// opening either one warms the other) narrowed to what the user is watching.
  Future<void> _loadCalendar({bool force = false}) async {
    final auth = context.read<AuthService>();
    final token = auth.token;
    if (!auth.isLoggedIn || token == null) return;
    final userId = auth.user?['id'] as int?;
    final cache = context.read<ApiCache>();
    void show(List<Map<String, dynamic>> week) {
      if (mounted) setState(() => _weeklySchedule = DiscoverApi.currentlyWatching(week));
    }

    try {
      if (userId == null) {
        // Account id not fetched yet, so there is no cache namespace for it.
        show(await _discover.weekSchedule(token: token));
        return;
      }
      await cache.load<List<Map<String, dynamic>>>(
        key: ApiCache.userKey(userId, DiscoverApi.weekCacheName(DateTime.now())),
        fetch: () => _discover.weekSchedule(token: token),
        decode: DiscoverApi.decodeSchedule,
        onData: (week, {required isFresh}) => show(week),
        maxAge: _scheduleMaxAge,
        force: force,
      );
    } on Exception catch (e) {
      debugPrint('[HomeScreen] Loading the weekly schedule failed: $e');
    }
  }

  bool get _hasAnySection => [
        _trending, _seasonal, _popular, _topAiring,
        _trendingManga, _topManga, _manhwa,
      ].any((items) => items.isNotEmpty);

  /// Shows each section from the cache right away and refreshes it once the
  /// cached copy is older than [_sectionMaxAge] (or always when [force]).
  Future<void> _load({bool force = false}) async {
    setState(() {
      _hasError = false;
      _loading = !_hasAnySection;
    });
    final cache = context.read<ApiCache>();
    // Cache keys use the untranslated season, e.g. `WINTER-2026`.
    final (seasonName, seasonYear) = _currentSeason;
    final (nextSeasonName, nextSeasonYear) = _nextSeason;
    final season = '$seasonName-$seasonYear';
    final nextSeason = '$nextSeasonName-$nextSeasonYear';

    Future<void> section(
      String key,
      Future<List<dynamic>> Function() fetch,
      void Function(List<dynamic> items) apply,
    ) async {
      try {
        await cache.load<List<dynamic>>(
          key: key,
          fetch: fetch,
          decode: (json) => json as List<dynamic>,
          onData: (items, {required isFresh}) {
            if (!mounted) return;
            setState(() {
              apply(items);
              _loading = false;
            });
          },
          maxAge: _sectionMaxAge,
          force: force,
          // The service returns [] on HTTP errors; never let that replace
          // good cached data.
          isValid: (items) => items.isNotEmpty,
        );
      } on Exception catch (e) {
        debugPrint('[HomeScreen] Loading $key failed: $e');
      }
    }

    try {
      await Future.wait([
        section('discover:trending', _service.getTrending,
            (items) => _trending = items),
        section('discover:season:$season', _service.getThisSeason,
            (items) => _seasonal = items),
        section('discover:nextSeason:$nextSeason', _service.getNextSeason,
            (items) => _popular = items),
        section('discover:topAiring', _service.getTopAiring,
            (items) => _topAiring = items),
        section('discover:trendingManga', _service.getTrendingManga,
            (items) => _trendingManga = items),
        section('discover:topManga', _service.getTopManga,
            (items) => _topManga = items),
        section('discover:manhwa', _service.getManhwa,
            (items) => _manhwa = items),
      ]);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = !_hasAnySection;
        });
      }
    }
  }

  /// AniList season (`WINTER`…`FALL`) and year airing now.
  (String, int) get _currentSeason {
    final month = DateTime.now().month;
    final year = DateTime.now().year;
    String season;
    if (month >= 1 && month <= 3) { season = 'WINTER'; }
    else if (month >= 4 && month <= 6) { season = 'SPRING'; }
    else if (month >= 7 && month <= 9) { season = 'SUMMER'; }
    else { season = 'FALL'; }
    return (season, year);
  }

  (String, int) get _nextSeason {
    final month = DateTime.now().month;
    final year = DateTime.now().year;
    if (month >= 10) return ('WINTER', year + 1);
    if (month >= 7) return ('FALL', year);
    if (month >= 4) return ('SUMMER', year);
    return ('SPRING', year);
  }

  static const _seasonKeys = {
    'WINTER': 'home_season_winter',
    'SPRING': 'home_season_spring',
    'SUMMER': 'home_season_summer',
    'FALL': 'home_season_fall',
  };

  /// Section header [key] filled with the translated [season], e.g.
  /// `CURRENT SEASON - WINTER 2026`.
  String _seasonHeader(String key, (String, int) season, String lang) {
    final (name, year) = season;
    return trf(key, lang, {
      'season': tr(_seasonKeys[name] ?? name, lang),
      'year': year,
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('nav_discover', lang),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
              child: AbsorbPointer(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: tr('search', lang),
                    prefixIcon:
                        const Icon(Icons.search, size: 20, color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: FadeSwitcher(
              child: _loading
                  ? _buildShimmer()
                  : _hasError
                      ? _buildError()
                      : _buildSections(lang),
            ),
          ),
        ],
      ),
    );
  }

  // Each row has its own hero scope: one media can be in several rows, and
  // two covers with one tag on a page break the flight to the detail page.
  Widget _buildSections(String lang) => RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildShortcuts(lang),
              if (_weeklySchedule.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionHeader(tr('home_this_week', lang), lang, onSeeAll: _openCalendar),
                const SizedBox(height: 10),
                _buildWeeklySchedule(lang),
                const SizedBox(height: 8),
                const Divider(indent: 16, endIndent: 16),
              ],
              const SizedBox(height: 12),
              _sectionHeader(tr('trending', lang), lang, browse: BrowseQuery.trending, items: _trending),
              const SizedBox(height: 10),
              _buildHorizontalRow(_trending, heroScope: 'home-trending'),
              const SizedBox(height: 20),
              _sectionHeader(_seasonHeader('home_current_season', _currentSeason, lang), lang,
                  onSeeAll: () => _openSeason(_currentSeason)),
              const SizedBox(height: 10),
              _buildHorizontalRow(_seasonal, heroScope: 'home-season'),
              const SizedBox(height: 20),
              _sectionHeader(_seasonHeader('home_upcoming_season', _nextSeason, lang), lang,
                  onSeeAll: () => _openSeason(_nextSeason)),
              const SizedBox(height: 10),
              _buildHorizontalRow(_popular, heroScope: 'home-next-season'),
              const SizedBox(height: 20),
              _sectionHeader(tr('top_airing', lang), lang, browse: BrowseQuery.topAiring, items: _topAiring),
              const SizedBox(height: 10),
              _buildHorizontalRow(_topAiring, heroScope: 'home-top-airing'),
              const SizedBox(height: 28),
              const Divider(indent: 16, endIndent: 16),
              const SizedBox(height: 16),
              _sectionHeader(tr('home_trending_manga', lang), lang,
                  browse: BrowseQuery.trendingManga, items: _trendingManga),
              const SizedBox(height: 10),
              _buildHorizontalRow(_trendingManga, heroScope: 'home-trending-manga'),
              const SizedBox(height: 20),
              _sectionHeader(tr('home_top_manga', lang), lang, browse: BrowseQuery.topManga, items: _topManga),
              const SizedBox(height: 10),
              _buildHorizontalRow(_topManga, heroScope: 'home-top-manga'),
              const SizedBox(height: 20),
              _sectionHeader(tr('home_popular_manhwa', lang), lang, browse: BrowseQuery.manhwa, items: _manhwa),
              const SizedBox(height: 10),
              _buildHorizontalRow(_manhwa, heroScope: 'home-manhwa'),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );

  void _openCalendar() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CalendarScreen()),
      );

  void _openSeason((String, int) season) {
    final (name, year) = season;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeasonScreen(initial: SeasonYear.tryParse(name, year)),
      ),
    );
  }

  /// "Calendar" and "Seasons" shortcuts at the top of Discover.
  Widget _buildShortcuts(String lang) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _openCalendar,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: Text(tr('cal_shortcut', lang), overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _openSeason(_currentSeason),
                icon: const Icon(Icons.grid_view_outlined, size: 18),
                label: Text(tr('season_shortcut', lang), overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      );

  /// Section title with a "See all" link that runs [onSeeAll], or else
  /// opens the row's [browse] query as a filterable grid, starting with its
  /// [items], when there are any.
  Widget _sectionHeader(String title, String lang,
      {BrowseQuery? browse, List<dynamic> items = const [], VoidCallback? onSeeAll}) {
    final seeAll = onSeeAll ??
        (browse != null && items.isNotEmpty
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BrowseScreen(title: title, query: browse, initialItems: items),
                  ),
                )
            : null);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (seeAll != null)
              GestureDetector(
                onTap: seeAll,
                child: Builder(builder: (ctx) => Text(
                  tr('home_see_all', lang),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                )),
              ),
          ],
        ),
      );
  }

  Widget _buildHorizontalRow(List<dynamic> items, {required String heroScope}) => SizedBox(
        height: 222,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          itemCount: items.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 120,
              child: AnimeCard(animeData: items[i], heroScope: heroScope),
            ),
          ),
        ),
      );

  static const _weekdayKeys = [
    'home_day_mon', 'home_day_tue', 'home_day_wed', 'home_day_thu',
    'home_day_fri', 'home_day_sat', 'home_day_sun',
  ];

  Widget _buildWeeklySchedule(String lang) {
    final settings = context.read<SettingsProvider>();

    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 16, right: 8),
        itemCount: _weeklySchedule.length,
        itemBuilder: (ctx, i) {
          final item = _weeklySchedule[i];
          final media = item['media'] as Map<String, dynamic>? ?? {};
          final id = media['id'] as int?;
          final cover = media['coverImage']?['large'] as String?;
          final title = settings.resolveTitle(media['title'] as Map<String, dynamic>?);
          final airingAt = (item['airingAt'] as num?)?.toInt() ?? 0;
          final episode = (item['episode'] as num?)?.toInt() ?? 0;
          final dt = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);
          final dayLabel = tr(_weekdayKeys[dt.weekday - 1], lang);
          final timeLabel = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          // A show can air more than once this week, so the scope is per card.
          final heroTag = id == null ? null : coverHeroTag('home-week-$i', id);
          final placeholder = ColoredBox(color: Theme.of(ctx).colorScheme.surfaceContainerHighest);

          return Pressable(
            onTap: id != null
                ? () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => DetailScreen(animeId: id, heroTag: heroTag, initialCoverUrl: cover),
                      ),
                    )
                : null,
            child: Container(
              width: 220,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    height: 130,
                    child: RoundedHero(
                      tag: heroTag,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                      child: cover != null
                          ? CachedNetworkImage(
                              imageUrl: cover,
                              fit: BoxFit.cover,
                              memCacheWidth: 140,
                              fadeInDuration: AppMotion.of(ctx, AppMotion.short),
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, _) => placeholder,
                              errorWidget: (_, _, _) => placeholder,
                            )
                          : placeholder,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Builder(builder: (c) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(c).colorScheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$dayLabel  $timeLabel',
                              style: TextStyle(fontSize: 10, color: Theme.of(c).colorScheme.primary, fontWeight: FontWeight.w600),
                            ),
                          )),
                          const SizedBox(height: 6),
                          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(trf('list_episode_n', lang, {'n': episode}),
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildError() {
    final lang = context.watch<SettingsProvider>().language;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(tr('load_error', lang),
              style: const TextStyle(color: Colors.grey)),
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

  Widget _buildShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
        baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDark ? Colors.grey[600]! : Colors.grey[100]!,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The Calendar and Seasons shortcuts, so the rows don't shift
              // down when the content replaces this.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    for (var i = 0; i < 2; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ...List.generate(7, (_) => _shimmerSection()),
            ],
          ),
        ),
      );
  }

  Widget _shimmerSection() => Column(

        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Container(
              width: 120,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          SizedBox(
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 6,
              itemBuilder: (_, _) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 170,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 100,
                      height: 12,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}
