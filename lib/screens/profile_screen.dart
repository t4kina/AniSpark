import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../services/anilist_service.dart';
import '../utils/score_utils.dart';
import '../utils/translations.dart' show tr, trf;
import '../utils/refresh_notifier.dart';
import '../theme/app_motion.dart';
import '../utils/tab_reselect.dart';
import '../widgets/motion/fade_switcher.dart';
import '../widgets/profile/favourite_cards.dart';
import '../widgets/profile/profile_card.dart';
import '../main.dart' show MainNavigation;
import 'settings_screen.dart';
import 'user_profile_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Only reachable signed in: AuthGate shows the login screen instead of
    // the tabs otherwise. Nothing for the frame in which a session ends.
    final signedIn = context.select<AuthService, bool>((auth) => auth.isLoggedIn);
    return signedIn ? const _LoggedInProfile() : const SizedBox.shrink();
  }
}

// ─── Logged In Profile ─────────────────────────────────────────────────────

class _LoggedInProfile extends StatefulWidget {
  const _LoggedInProfile();

  @override
  State<_LoggedInProfile> createState() => _LoggedInProfileState();
}

class _LoggedInProfileState extends State<_LoggedInProfile> {
  // The activity heatmap alone takes up to 6 requests, so stats are only
  // refreshed automatically once they are this old (pull-to-refresh forces).
  static const _statsMaxAge = Duration(minutes: 30);

  /// The profile's index in the bottom navigation.
  static const _profileTab = 4;

  /// Hero scope of the favourite covers.
  static const _favsHeroScope = 'profile-favs';

  final _service = AniListService();
  final _scrollController = ScrollController();
  late final VoidCallback _stopReselectListener;
  int _followersCount = 0;
  int _followingCount = 0;
  List<dynamic> _favoriteAnime = [];
  List<dynamic> _favoriteCharacters = [];
  String? _bannerImage;
  bool _statsLoaded = false;
  Map<String, int> _activityDays = {};
  List<dynamic> _following = [];
  bool _animeGenresExpanded = false;
  bool _mangaGenresExpanded = false;
  bool _scoreDistributionExpanded = false;
  bool _releaseYearsExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthService>();
      final cached = auth.profileExtras;
      if (cached != null) _loadFromCache(cached);
      // Show the cached profile instantly, refreshing it in the background
      // once it is older than [_statsMaxAge] (or was saved without a date).
      final savedAt = cached?['savedAt'] as int?;
      final age = savedAt == null
          ? null
          : DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
      if (age == null || age.isNegative || age > _statsMaxAge) _fetchStats();
    });
    profileRefreshNotifier.addListener(_onRefresh);
    _stopReselectListener = scrollToTopOnReselect(
      tabReselectedNotifier,
      tab: _profileTab,
      onReselected: () => scrollToTop(_scrollController, animate: !AppMotion.reduced(context)),
    );
  }

  void _loadFromCache(Map<String, dynamic> cached) {
    if (!mounted) return;
    setState(() {
      _bannerImage = cached['bannerImage'] as String?;
      _favoriteAnime = List<dynamic>.from(cached['favoriteAnime'] as List? ?? []);
      _favoriteCharacters = List<dynamic>.from(cached['favoriteCharacters'] as List? ?? []);
      _followersCount = (cached['followersCount'] as num?)?.toInt() ?? 0;
      _followingCount = (cached['followingCount'] as num?)?.toInt() ?? 0;
      _activityDays = (cached['activityDays'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num).toInt()));
      _following = List<dynamic>.from(cached['following'] as List? ?? []);
      _statsLoaded = true;
    });
  }

  @override
  void dispose() {
    profileRefreshNotifier.removeListener(_onRefresh);
    _stopReselectListener();
    _scrollController.dispose();
    super.dispose();
  }

  void _onRefresh() => _fetchStats();

  Future<void> _fetchStats() async {
    final auth = context.read<AuthService>();
    final userId = auth.user?['id'] as int?;
    if (userId == null || auth.token == null) return;

    // Use banner from auth if available immediately
    if (mounted) {
      setState(() => _bannerImage = auth.user?['bannerImage'] as String?);
    }

    final List<Object> results;
    try {
      results = await Future.wait([
        _service.getUserProfileStats(userId, auth.token!),
        _service.getUserFollowCounts(userId, auth.token!),
        _service.getUserActivityDays(userId, auth.token!),
        _service.getFollowing(userId, auth.token!),
      ]);
    } on Exception catch (e) {
      // Keep whatever is already on screen (cached stats) and try next time.
      debugPrint('[ProfileScreen] Loading stats failed: $e');
      return;
    }

    if (!mounted) return;
    final statsResult = results[0] as Map<String, dynamic>;
    final followResult = results[1] as Map<String, int>;
    final activityResult = results[2] as Map<String, int>;
    final followingResult = results[3] as List<dynamic>;

    final user = statsResult['user'] as Map<String, dynamic>?;
    final newBanner = (user?['bannerImage'] as String?) ?? _bannerImage;
    final newFavAnime = (user?['favourites']?['anime']?['nodes'] as List<dynamic>?) ?? [];
    final newFavChars = (user?['favourites']?['characters']?['nodes'] as List<dynamic>?) ?? [];
    final newFollowers = followResult['followers'] ?? 0;
    final newFollowing = followResult['following'] ?? 0;

    setState(() {
      _bannerImage = newBanner;
      _favoriteAnime = newFavAnime;
      _favoriteCharacters = newFavChars;
      _followersCount = newFollowers;
      _followingCount = newFollowing;
      _activityDays = activityResult;
      _following = followingResult;
      _statsLoaded = true;
    });

    // Persist so next launch loads instantly without re-fetching
    auth.saveProfileExtras({
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'bannerImage': newBanner,
      'favoriteAnime': newFavAnime,
      'favoriteCharacters': newFavChars,
      'followersCount': newFollowers,
      'followingCount': newFollowing,
      'activityDays': activityResult,
      'following': followingResult,
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final lang = context.watch<SettingsProvider>().language;
    final user = auth.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final animeStats =
        user['statistics']?['anime'] as Map<String, dynamic>?;
    final mangaStats =
        user['statistics']?['manga'] as Map<String, dynamic>?;
    final scoreFormat = scoreFormatOf(user);
    final avatar = user['avatar']?['large'] as String?;
    final name = user['name'] as String? ?? tr('feed_unknown', lang);

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
        onRefresh: _fetchStats,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // ── Who you are and your stats, on your banner ──────────────
            SliverToBoxAdapter(
              child: ProfileCard(
                name: name,
                lang: lang,
                avatarUrl: avatar,
                bannerUrl: _bannerImage,
                animeStats: animeStats,
                mangaStats: mangaStats,
                scoreFormat: scoreFormat,
                onCountTap: (type) => MainNavigation.navigateToTab(type == 'MANGA' ? 1 : 0),
                cornerButton: ProfileCard.roundButton(
                  icon: Icons.settings_outlined,
                  tooltip: tr('tooltip_settings', lang),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
                actions: [
                  ProfileCard.primaryButton(
                    label: '$_followersCount ${tr('followers', lang)}',
                    onPressed: () => _showFollowSheet(context, tr('followers', lang)),
                  ),
                  ProfileCard.secondaryButton(
                    label: '$_followingCount ${tr('following', lang)}',
                    onPressed: () => _showFollowSheet(context, tr('following', lang), preloaded: _following),
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(
              child: Builder(builder: (ctx) => Divider(height: 1, color: Theme.of(ctx).colorScheme.outline)),
            ),

            // ── Favorite Anime ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Text(tr('favorite_anime', lang),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        letterSpacing: 0.5)),
              ),
            ),
            // The favourites fade in once the stats arrive.
            SliverToBoxAdapter(
              child: FadeSwitcher(
                child: !_statsLoaded
                    ? const SizedBox(key: ValueKey('fav-anime-pending'), height: 170)
                    : _favoriteAnime.isEmpty
                        ? Container(
                            key: const ValueKey('fav-anime-none'),
                            // Full width, so the message stays left-aligned.
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(tr('no_favourites', lang),
                                style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          )
                        : SizedBox(
                            key: const ValueKey('fav-anime'),
                            width: double.infinity,
                            height: 170,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _favoriteAnime.length,
                              itemBuilder: (_, i) => FavouriteMediaCard(
                                media: _favoriteAnime[i] as Map<String, dynamic>,
                                heroScope: _favsHeroScope,
                              ),
                            ),
                          ),
              ),
            ),

            // ── Favorite Characters ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Text(tr('favorite_characters', lang),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        letterSpacing: 0.5)),
              ),
            ),
            SliverToBoxAdapter(
              child: FadeSwitcher(
                child: !_statsLoaded
                    ? const SizedBox(key: ValueKey('fav-chars-pending'), height: 120)
                    : _favoriteCharacters.isEmpty
                        ? Container(
                            key: const ValueKey('fav-chars-none'),
                            // Full width, so the message stays left-aligned.
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(tr('no_favourites', lang),
                                style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          )
                        : SizedBox(
                            key: const ValueKey('fav-chars'),
                            width: double.infinity,
                            height: 120,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _favoriteCharacters.length,
                              itemBuilder: (_, i) => FavouriteCharacterCard(
                                character: _favoriteCharacters[i] as Map<String, dynamic>,
                              ),
                            ),
                          ),
              ),
            ),

            // ── Activity Graph ──────────────────────────────────────────
            SliverToBoxAdapter(child: _buildActivityGraph(lang)),

            // ── Top Genres ─────────────────────────────────────────────
            SliverToBoxAdapter(child: _buildTopGenres(animeStats, mangaStats, lang, scoreFormat)),

            // ── Score Distribution ──────────────────────────────────────
            SliverToBoxAdapter(child: _buildScoreDistribution(animeStats, mangaStats, lang, scoreFormat)),

            // ── Release Years ───────────────────────────────────────────
            SliverToBoxAdapter(child: _buildReleaseYears(animeStats, lang)),


            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
        ],
      ),
    );
  }

  void _showFollowSheet(BuildContext context, String title,
      {List<dynamic>? preloaded}) {
    final auth = context.read<AuthService>();
    final userId = auth.user?['id'] as int?;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FollowSheet(
        title: title,
        preloaded: preloaded,
        userId: userId,
        token: auth.token,
        service: _service,
      ),
    );
  }

  /// A heatmap day as text, e.g. "Jan 5, 2025" in English.
  static String _heatmapDate(DateTime day, String lang) =>
      trf('profile_date', lang, {
        'month': tr(_monthKeys[day.month - 1], lang),
        'day': day.day,
        'year': day.year,
      });

  static const _monthKeys = [
    'profile_month_jan', 'profile_month_feb', 'profile_month_mar',
    'profile_month_apr', 'profile_month_may', 'profile_month_jun',
    'profile_month_jul', 'profile_month_aug', 'profile_month_sep',
    'profile_month_oct', 'profile_month_nov', 'profile_month_dec',
  ];

  Widget _buildActivityGraph(String lang) {
    // Build a 52-week heatmap (oldest left → newest right)
    final today = DateTime.now();
    // Start from Monday of the week 52 weeks ago
    final startRaw = today.subtract(const Duration(days: 364));
    final startDay =
        startRaw.subtract(Duration(days: startRaw.weekday - 1)); // Monday

    final totalDays = today.difference(startDay).inDays + 1;
    final totalWeeks = (totalDays / 7).ceil();

    final maxCount = _activityDays.values.fold(0, (a, b) => a > b ? a : b);

    Color cellColor(int count, BuildContext ctx) {
      final accent = Theme.of(ctx).colorScheme.primary;
      if (count == 0) return Theme.of(ctx).colorScheme.surfaceContainerHighest;
      if (maxCount == 0) return accent;
      final ratio = count / maxCount;
      if (ratio < 0.25) return accent.withValues(alpha: 0.25);
      if (ratio < 0.50) return accent.withValues(alpha: 0.50);
      if (ratio < 0.75) return accent.withValues(alpha: 0.75);
      return accent;
    }

    const cellSize = 13.0;
    const gap = 3.0;
    const step = cellSize + gap;

    String? tooltip;

    return Padding(
      // The bottom gap keeps the legend clear of the genre cards below.
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('profile_activity', lang),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Builder(builder: (ctx) {
            return StatefulBuilder(builder: (ctx, setLocal) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // Opens on the latest weeks; older ones are a swipe left.
                    reverse: true,
                    child: GestureDetector(
                      onTapUp: (details) {
                        final x = details.localPosition.dx;
                        final y = details.localPosition.dy;
                        final week = (x / step).floor();
                        final dow = (y / step).floor();
                        if (week < 0 || week >= totalWeeks || dow < 0 || dow >= 7) return;
                        final day = startDay.add(Duration(days: week * 7 + dow));
                        if (day.isAfter(today)) return;
                        final key =
                            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                        final count = _activityDays[key] ?? 0;
                        final date = _heatmapDate(day, lang);
                        setLocal(() => tooltip = count == 0
                            ? trf('profile_no_activity_on', lang, {'date': date})
                            : trf(
                                count == 1
                                    ? 'profile_activity_on_one'
                                    : 'profile_activity_on_many',
                                lang,
                                {'n': count, 'date': date}));
                      },
                      child: SizedBox(
                        width: totalWeeks * step,
                        height: 7 * step - gap,
                        child: CustomPaint(
                          painter: _HeatmapPainter(
                            startDay: startDay,
                            today: today,
                            totalWeeks: totalWeeks,
                            activityDays: _activityDays,
                            cellColor: (count) => cellColor(count, ctx),
                            cellSize: cellSize,
                            gap: gap,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (tooltip != null) ...[
                    const SizedBox(height: 6),
                    Text(tooltip!,
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.55))),
                  ],
                ],
              );
            });
          }),
          const SizedBox(height: 6),
          Builder(builder: (ctx) => Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(tr('profile_less', lang),
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(width: 4),
              ...List.generate(5, (i) {
                final accent = Theme.of(ctx).colorScheme.primary;
                final colors = [
                  Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  accent.withValues(alpha: 0.25),
                  accent.withValues(alpha: 0.50),
                  accent.withValues(alpha: 0.75),
                  accent,
                ];
                return Container(
                  width: cellSize,
                  height: cellSize,
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: colors[i],
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
              const SizedBox(width: 4),
              Text(tr('profile_more', lang),
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          )),
        ],
      ),
    );
  }

  Widget _buildTopGenres(Map<String, dynamic>? animeStats,
      Map<String, dynamic>? mangaStats, String lang, String? scoreFormat) {
    return Column(
      children: [
        _genreSection(
          label: tr('profile_anime_genres', lang),
          stats: animeStats,
          countKey: 'profile_n_anime',
          lang: lang,
          scoreFormat: scoreFormat,
          expanded: _animeGenresExpanded,
          onToggle: () => setState(() => _animeGenresExpanded = !_animeGenresExpanded),
        ),
        _genreSection(
          label: tr('profile_manga_genres', lang),
          stats: mangaStats,
          countKey: 'profile_n_manga',
          lang: lang,
          scoreFormat: scoreFormat,
          expanded: _mangaGenresExpanded,
          onToggle: () => setState(() => _mangaGenresExpanded = !_mangaGenresExpanded),
        ),
      ],
    );
  }

  /// A dashboard section: a rounded card whose header expands and collapses
  /// [body], or notes that there's nothing to show when [hasData] is false.
  Widget _dashboardCard({
    required String title,
    required String lang,
    required bool hasData,
    required bool expanded,
    required VoidCallback onToggle,
    required WidgetBuilder body,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: hasData ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.5)),
                  ),
                  if (hasData)
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: AppMotion.of(context, AppMotion.short),
                      curve: AppMotion.standard,
                      child: const Icon(Icons.expand_more, size: 18, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(tr('profile_no_data', lang),
                  style: TextStyle(fontSize: 12, color: Colors.grey.withValues(alpha: 0.7))),
            )
          else
            AnimatedSize(
              duration: AppMotion.of(context, AppMotion.medium),
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: body(context))
                  : const SizedBox(width: double.infinity),
            ),
        ],
      ),
    );
  }

  /// A rounded bar filled to [ratio], the accent brightening toward its
  /// end: the one mark the genre and era rows share.
  Widget _dashboardBar(double ratio) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 8,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(4)),
      child: FractionallySizedBox(
        widthFactor: ratio.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(colors: [colors.primary.withValues(alpha: 0.55), colors.primary]),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// A statistics score (AniList sends them on 0–100) in the user's score
  /// format, like every other score in the app.
  static String _statScore(num score, String? format) => formatScore(score / 10, format);

  /// [countKey] is the translation of "{n} titles" for this media type.
  Widget _genreSection({
    required String label,
    required Map<String, dynamic>? stats,
    required String countKey,
    required String lang,
    required String? scoreFormat,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    final raw = stats?['genres'] as List<dynamic>?;
    return _dashboardCard(
      title: label,
      lang: lang,
      hasData: raw != null && raw.isNotEmpty,
      expanded: expanded,
      onToggle: onToggle,
      body: (context) {
        final top = (raw!.cast<Map<String, dynamic>>().toList()
              ..sort((a, b) => ((b['count'] as num?) ?? 0).compareTo((a['count'] as num?) ?? 0)))
            .take(5)
            .toList();
        final maxCount = ((top.first['count'] as num?) ?? 0).toDouble();
        return Column(
          children: [
            for (final (i, g) in top.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                child: _genreRow(g, maxCount, countKey, lang, scoreFormat),
              ),
          ],
        );
      },
    );
  }

  Widget _genreRow(Map<String, dynamic> genre, double maxCount, String countKey, String lang, String? scoreFormat) {
    final count = (genre['count'] as num?)?.toInt() ?? 0;
    final mean = (genre['meanScore'] as num?) ?? 0;
    var details = trf(countKey, lang, {'n': count});
    if (mean > 0) {
      final score = _statScore(mean, scoreFormat);
      details += scoreFormat == 'POINT_3' ? '  ·  $score' : '  ·  $score ★';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(genre['genre'] as String? ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Text(details,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey, fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
        const SizedBox(height: 6),
        _dashboardBar(maxCount > 0 ? count / maxCount : 0),
      ],
    );
  }

  Widget _buildScoreDistribution(Map<String, dynamic>? animeStats,
      Map<String, dynamic>? mangaStats, String lang, String? scoreFormat) {
    final animeRaw = animeStats?['scores'] as List<dynamic>?;
    final mangaRaw = mangaStats?['scores'] as List<dynamic>?;
    if ((animeRaw == null || animeRaw.isEmpty) &&
        (mangaRaw == null || mangaRaw.isEmpty)) {
      return const SizedBox.shrink();
    }
    const caption = TextStyle(fontSize: 12, color: Colors.grey);
    return _dashboardCard(
      title: tr('profile_score_distribution', lang),
      lang: lang,
      hasData: true,
      expanded: _scoreDistributionExpanded,
      onToggle: () => setState(() => _scoreDistributionExpanded = !_scoreDistributionExpanded),
      body: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('nav_anime', lang), style: caption),
          const SizedBox(height: 8),
          _scoreChart(animeRaw, lang, scoreFormat),
          const SizedBox(height: 16),
          Text(tr('nav_manga', lang), style: caption),
          const SizedBox(height: 8),
          _scoreChart(mangaRaw, lang, scoreFormat),
        ],
      ),
    );
  }

  /// One bar per score the user has given, as tall as how often they gave
  /// it, labelled in their score format. Bars keep a slim width however few
  /// there are; past a dozen different scores they're grouped by whole
  /// point so they stay readable.
  Widget _scoreChart(List<dynamic>? raw, String lang, String? scoreFormat) {
    final counts = <int, int>{};
    for (final e in (raw ?? const []).cast<Map<String, dynamic>>()) {
      final score = ((e['score'] as num?) ?? 0).toInt();
      final count = ((e['count'] as num?) ?? 0).toInt();
      if (score > 0 && count > 0) counts[score] = (counts[score] ?? 0) + count;
    }
    if (counts.isEmpty) {
      return Text(tr('profile_no_data', lang),
          style: TextStyle(fontSize: 12, color: Colors.grey.withValues(alpha: 0.6)));
    }
    final grouped = counts.length <= 12
        ? counts
        : {
            for (final score in {for (final s in counts.keys) ((s - 1) ~/ 10 + 1) * 10})
              score: counts.entries
                  .where((e) => ((e.key - 1) ~/ 10 + 1) * 10 == score)
                  .fold<int>(0, (sum, e) => sum + e.value),
          };
    final bars = grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final maxCount = bars.map((e) => e.value).reduce(math.max);
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final bar in bars)
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Tooltip(
                        message: '${bar.value}',
                        child: Container(
                          height: math.max(4, 56 * bar.value / maxCount),
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                accent.withValues(alpha: 0.55 + 0.45 * bar.value / maxCount),
                                accent.withValues(alpha: 0.25 + 0.25 * bar.value / maxCount),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_statScore(bar.key, scoreFormat),
                            maxLines: 1, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReleaseYears(Map<String, dynamic>? animeStats, String lang) {
    final raw = animeStats?['releaseYears'] as List<dynamic>?;
    if (raw == null || raw.isEmpty) return const SizedBox.shrink();

    // Group into 5-year buckets
    final buckets = <int, int>{};
    for (final e in raw.cast<Map<String, dynamic>>()) {
      final year = ((e['releaseYear'] as num?) ?? 0).toInt();
      final count = ((e['count'] as num?) ?? 0).toInt();
      if (year <= 0 || count <= 0) continue;
      final bucket = (year ~/ 5) * 5;
      buckets[bucket] = (buckets[bucket] ?? 0) + count;
    }
    if (buckets.isEmpty) return const SizedBox.shrink();

    // Newest first: what the user watches now leads.
    final sortedBuckets = buckets.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final maxCount = sortedBuckets.map((e) => e.value).reduce(math.max);
    const label = TextStyle(fontSize: 11, color: Colors.grey, fontFeatures: [FontFeature.tabularFigures()]);

    return _dashboardCard(
      title: tr('profile_titles_by_era', lang),
      lang: lang,
      hasData: true,
      expanded: _releaseYearsExpanded,
      onToggle: () => setState(() => _releaseYearsExpanded = !_releaseYearsExpanded),
      body: (context) => Column(
        children: [
          for (final (i, entry) in sortedBuckets.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: Row(
                children: [
                  SizedBox(width: 72, child: Text('${entry.key}–${entry.key + 4}', style: label)),
                  const SizedBox(width: 8),
                  Expanded(child: _dashboardBar(entry.value / maxCount)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 30,
                    child: Text('${entry.value}',
                        textAlign: TextAlign.end, style: label.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

}

class _HeatmapPainter extends CustomPainter {
  final DateTime startDay;
  final DateTime today;
  final int totalWeeks;
  final Map<String, int> activityDays;
  final Color Function(int count) cellColor;
  final double cellSize;
  final double gap;

  const _HeatmapPainter({
    required this.startDay,
    required this.today,
    required this.totalWeeks,
    required this.activityDays,
    required this.cellColor,
    required this.cellSize,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final step = cellSize + gap;
    final paint = Paint();

    for (int week = 0; week < totalWeeks; week++) {
      for (int dow = 0; dow < 7; dow++) {
        final day = startDay.add(Duration(days: week * 7 + dow));
        if (day.isAfter(today)) continue;

        final key =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        final count = activityDays[key] ?? 0;

        paint.color = cellColor(count);
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            week * step,
            dow * step,
            cellSize,
            cellSize,
          ),
          const Radius.circular(2),
        );
        canvas.drawRRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.activityDays != activityDays || old.today != today;
}

// ── Follow sheet ──────────────────────────────────────────────────────────────

class _FollowSheet extends StatefulWidget {
  final String title;
  final List<dynamic>? preloaded;
  final int? userId;
  final String? token;
  final AniListService service;

  const _FollowSheet({
    required this.title,
    required this.service,
    this.preloaded,
    this.userId,
    this.token,
  });

  @override
  State<_FollowSheet> createState() => _FollowSheetState();
}

class _FollowSheetState extends State<_FollowSheet> {
  List<dynamic>? _users;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.preloaded != null) {
      _users = widget.preloaded;
    } else {
      _fetchFollowers();
    }
  }

  Future<void> _fetchFollowers() async {
    if (widget.userId == null || widget.token == null) {
      setState(() => _users = []);
      return;
    }
    setState(() => _loading = true);
    final result = await widget.service.getFollowers(widget.userId!, widget.token!);
    if (mounted) setState(() { _users = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lang = context.watch<SettingsProvider>().language;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(widget.title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_users == null || _users!.isEmpty)
                      ? Center(child: Text(tr('profile_nobody_here', lang),
                          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4))))
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _users!.length,
                          itemBuilder: (_, i) => _UserTile(user: _users![i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final dynamic user;
  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final u = user as Map<String, dynamic>;
    final id = u['id'] as int?;
    final name = u['name'] as String? ?? '';
    final avatar = u['avatar']?['large'] as String?;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
        child: avatar == null ? const Icon(Icons.person, size: 22) : null,
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
      onTap: id != null
          ? () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => UserProfileScreen(
                    userId: id, name: name, avatarUrl: avatar)))
          : null,
    );
  }
}
