import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/anilist_service.dart';
import '../utils/refresh_notifier.dart';
import '../widgets/overlay_button.dart';
import 'settings_screen.dart';
import 'user_profile_screen.dart';
import 'detail_screen.dart';
import 'character_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return auth.isLoggedIn ? const _LoggedInProfile() : const _LoginPrompt();
  }
}

// ─── Login Prompt ──────────────────────────────────────────────────────────

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt();

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Builder(builder: (ctx) => Icon(Icons.person,
                    size: 50, color: Theme.of(ctx).colorScheme.primary)),
              ),
              const SizedBox(height: 24),
              const Text('Connect your AniList',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Login to sync your anime list and track your progress across devices.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    try {
                      await auth.login();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Login failed: $e')),
                        );
                      }
                    }
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.login, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Login with AniList',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Logged In Profile ─────────────────────────────────────────────────────

class _LoggedInProfile extends StatefulWidget {
  const _LoggedInProfile();

  @override
  State<_LoggedInProfile> createState() => _LoggedInProfileState();
}

class _LoggedInProfileState extends State<_LoggedInProfile> {
  final _service = AniListService();
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
      if (cached != null) {
        _loadFromCache(cached);
      } else {
        _fetchStats();
      }
    });
    profileRefreshNotifier.addListener(_onRefresh);
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

    final results = await Future.wait([
      _service.getUserProfileStats(userId, auth.token!),
      _service.getUserFollowCounts(userId, auth.token!),
      _service.getUserActivityDays(userId, auth.token!),
      _service.getFollowing(userId, auth.token!),
    ]);

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
    final user = auth.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final animeStats =
        user['statistics']?['anime'] as Map<String, dynamic>?;
    final mangaStats =
        user['statistics']?['manga'] as Map<String, dynamic>?;
    final avatar = user['avatar']?['large'] as String?;
    final name = user['name'] as String? ?? 'Unknown';

    final minutesWatched = (animeStats?['minutesWatched'] as num?)?.toInt() ?? 0;
    final daysWatched = (minutesWatched / 1440).toStringAsFixed(1);
    final episodesWatched = (animeStats?['episodesWatched'] as num?)?.toInt() ?? 0;
    final totalAnime = (animeStats?['count'] as num?)?.toInt() ?? 0;
    final chaptersRead = (mangaStats?['chaptersRead'] as num?)?.toInt() ?? 0;
    final volumesRead = (mangaStats?['volumesRead'] as num?)?.toInt() ?? 0;
    final totalManga = (mangaStats?['count'] as num?)?.toInt() ?? 0;

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
        onRefresh: _fetchStats,
        child: CustomScrollView(
          slivers: [
            // ── Banner + Avatar Header + Stats bar (single sliver to avoid seam) ──
            SliverToBoxAdapter(
              child: _buildHeaderAndStats(
                avatar, name, context,
                totalAnime: totalAnime,
                episodesWatched: episodesWatched,
                daysWatched: daysWatched,
                totalManga: totalManga,
                chaptersRead: chaptersRead,
                volumesRead: volumesRead,
              ),
            ),

            // ── Follow pills ───────────────────────────────────────────
            SliverToBoxAdapter(child: _buildFollowPills(context)),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(
              child: Builder(builder: (ctx) => Divider(height: 1, color: Theme.of(ctx).colorScheme.outline)),
            ),

            // ── Favorite Anime ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: const Text('FAVORITE ANIME',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        letterSpacing: 0.5)),
              ),
            ),
            SliverToBoxAdapter(
              child: _favoriteAnime.isEmpty && _statsLoaded
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('No favourites yet',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    )
                  : SizedBox(
                      height: 170,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _favoriteAnime.length,
                        itemBuilder: (_, i) =>
                            _animeFavCard(_favoriteAnime[i]),
                      ),
                    ),
            ),

            // ── Favorite Characters ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: const Text('FAVORITE CHARACTERS',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        letterSpacing: 0.5)),
              ),
            ),
            SliverToBoxAdapter(
              child: _favoriteCharacters.isEmpty && _statsLoaded
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('No favourites yet',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    )
                  : SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _favoriteCharacters.length,
                        itemBuilder: (_, i) =>
                            _charFavCard(_favoriteCharacters[i]),
                      ),
                    ),
            ),

            // ── Activity Graph ──────────────────────────────────────────
            SliverToBoxAdapter(child: _buildActivityGraph()),

            // ── Top Genres ─────────────────────────────────────────────
            SliverToBoxAdapter(child: _buildTopGenres(animeStats, mangaStats)),

            // ── Score Distribution ──────────────────────────────────────
            SliverToBoxAdapter(child: _buildScoreDistribution(animeStats, mangaStats)),

            // ── Release Years ───────────────────────────────────────────
            SliverToBoxAdapter(child: _buildReleaseYears(animeStats)),


            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            right: 12,
            child: overlayBtn(
              icon: Icons.settings_outlined,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAndStats(
    String? avatar,
    String name,
    BuildContext context, {
    required int totalAnime,
    required int episodesWatched,
    required String daysWatched,
    required int totalManga,
    required int chaptersRead,
    required int volumesRead,
  }) {
    final topPadding = MediaQuery.of(context).padding.top;
    final surface = Theme.of(context).colorScheme.surface;
    final outline = Theme.of(context).colorScheme.outline;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Banner + Avatar + Name ──────────────────────────────
          Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  SizedBox(
                    height: 200 + topPadding,
                    width: double.infinity,
                    child: _bannerImage != null
                        ? CachedNetworkImage(
                            imageUrl: _bannerImage!,
                            fit: BoxFit.cover,
                            memCacheWidth: 800,
                            placeholder: (ctx, _) => Container(
                                color: Theme.of(ctx).colorScheme.surfaceContainerHighest),
                            errorWidget: (_, _, _) => Container(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest),
                          )
                        : Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            surface.withValues(alpha: 0.6),
                            surface,
                          ],
                          stops: const [0.3, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: surface, width: 3),
                          ),
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor:
                                Theme.of(context).colorScheme.surfaceContainerHighest,
                            backgroundImage: avatar != null
                                ? CachedNetworkImageProvider(avatar)
                                : null,
                            child: avatar == null
                                ? const Icon(Icons.person, size: 40, color: Colors.grey)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          name,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // ── Stats card ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: outline),
                  ),
                  child: Column(
                    children: [
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            _statItem('$totalAnime', 'Anime'),
                            _statDividerV(outline),
                            _statItem('$episodesWatched', 'Episodes'),
                            _statDividerV(outline),
                            _statItem(daysWatched, 'Days Watched'),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: outline),
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            _statItem('$totalManga', 'Manga'),
                            _statDividerV(outline),
                            _statItem('$chaptersRead', 'Chapters'),
                            _statDividerV(outline),
                            _statItem('$volumesRead', 'Volumes Read'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _animeFavCard(dynamic anime) {
    final a = anime as Map<String, dynamic>;
    final id = a['id'] as int?;
    final image = a['coverImage']?['large'] as String?;
    final title = (a['title']?['english'] ?? a['title']?['romaji'] ?? '') as String;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: id != null
            ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => DetailScreen(animeId: id)))
            : null,
        child: SizedBox(
          width: 100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: image != null
                    ? CachedNetworkImage(
                        imageUrl: image,
                        width: 100,
                        height: 140,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                      )
                    : Container(
                        width: 100, height: 140, color: Theme.of(context).colorScheme.surfaceContainerHighest),
              ),
              const SizedBox(height: 4),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _charFavCard(dynamic char) {
    final c = char as Map<String, dynamic>;
    final id = c['id'] as int?;
    final image = c['image']?['medium'] as String?;
    final name = c['name']?['full'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: id != null
            ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => CharacterScreen(
                    characterId: id, name: name, imageUrl: image)))
            : null,
        child: SizedBox(
          width: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: image != null
                    ? CachedNetworkImage(
                        imageUrl: image,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        memCacheWidth: 160,
                      )
                    : Container(
                        width: 80, height: 80, color: Theme.of(context).colorScheme.surfaceContainerHighest),
              ),
              const SizedBox(height: 4),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem(String value, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 10, letterSpacing: 0.2)),
            ],
          ),
        ),
      );

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

  Widget _buildFollowPills(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          _followPill(
            context, cs,
            count: _followersCount,
            label: 'Followers',
            icon: Icons.group_outlined,
            onTap: () => _showFollowSheet(context, 'Followers'),
          ),
          const SizedBox(width: 10),
          _followPill(
            context, cs,
            count: _followingCount,
            label: 'Following',
            icon: Icons.person_outlined,
            onTap: () => _showFollowSheet(context, 'Following', preloaded: _following),
          ),
        ],
      ),
    );
  }

  Widget _followPill(BuildContext context, ColorScheme cs, {
    required int count,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                '$count $label',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statDividerV(Color color) => VerticalDivider(
        width: 1, thickness: 1, color: color);

  Widget _buildActivityGraph() {
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
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ACTIVITY',
              style: TextStyle(
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
                        final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                        final label = '${months[day.month - 1]} ${day.day}, ${day.year}';
                        setLocal(() => tooltip = count == 0
                            ? 'No activity on $label'
                            : '$count activit${count == 1 ? 'y' : 'ies'} on $label');
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
              const Text('Less', style: TextStyle(fontSize: 10, color: Colors.grey)),
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
              const Text('More', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          )),
        ],
      ),
    );
  }

  Widget _buildTopGenres(
      Map<String, dynamic>? animeStats, Map<String, dynamic>? mangaStats) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _genreSection(
            label: 'ANIME GENRES',
            stats: animeStats,
            unit: 'anime',
            expanded: _animeGenresExpanded,
            onToggle: () => setState(() => _animeGenresExpanded = !_animeGenresExpanded),
          ),
          _genreSection(
            label: 'MANGA GENRES',
            stats: mangaStats,
            unit: 'manga',
            expanded: _mangaGenresExpanded,
            onToggle: () => setState(() => _mangaGenresExpanded = !_mangaGenresExpanded),
          ),
        ],
      ),
    );
  }

  Widget _genreSection({
    required String label,
    required Map<String, dynamic>? stats,
    required String unit,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    final raw = stats?['genres'] as List<dynamic>?;
    final hasData = raw != null && raw.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasData ? onToggle : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        letterSpacing: 0.5)),
                const Spacer(),
                Icon(
                  hasData
                      ? (expanded ? Icons.expand_less : Icons.expand_more)
                      : Icons.expand_more,
                  size: 18,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
        if (expanded && hasData) ...[
          const SizedBox(height: 4),
          Builder(builder: (ctx) {
            final genres = raw
                .cast<Map<String, dynamic>>()
                .toList()
              ..sort((a, b) => ((b['count'] as num?) ?? 0)
                  .compareTo((a['count'] as num?) ?? 0));
            final top = genres.take(5).toList();
            final maxCount = (top.first['count'] as num).toDouble();
            return Column(
              children: top.map((g) {
                final genre = g['genre'] as String? ?? '';
                final count = (g['count'] as num?)?.toInt() ?? 0;
                final score = (g['meanScore'] as num?)?.toDouble() ?? 0.0;
                final ratio = maxCount > 0 ? count / maxCount : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(genre,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                          Text(
                            '$count $unit${score > 0 ? '  ·  ${score.toStringAsFixed(1)} ★' : ''}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 5,
                          backgroundColor: Theme.of(ctx)
                              .colorScheme
                              .surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                              Theme.of(ctx).colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          }),
        ],
        Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
      ],
    );
  }

  Widget _buildScoreDistribution(
      Map<String, dynamic>? animeStats, Map<String, dynamic>? mangaStats) {
    final animeRaw = animeStats?['scores'] as List<dynamic>?;
    final mangaRaw = mangaStats?['scores'] as List<dynamic>?;
    if ((animeRaw == null || animeRaw.isEmpty) &&
        (mangaRaw == null || mangaRaw.isEmpty)) {
      return const SizedBox.shrink();
    }

    Widget scoreBar(List<dynamic>? raw) {
      if (raw == null || raw.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('No data', style: TextStyle(fontSize: 12, color: Colors.grey.withValues(alpha: 0.6))),
        );
      }
      final scores = raw
          .cast<Map<String, dynamic>>()
          .where((e) => ((e['score'] as num?) ?? 0) > 0 && ((e['count'] as num?) ?? 0) > 0)
          .toList()
        ..sort((a, b) => ((a['score'] as num?) ?? 0).compareTo((b['score'] as num?) ?? 0));
      if (scores.isEmpty) return const SizedBox.shrink();
      final maxAmount = scores
          .map((e) => (e['count'] as num?)?.toInt() ?? 0)
          .reduce((a, b) => a > b ? a : b);
      return Builder(builder: (ctx) {
        final accent = Theme.of(ctx).colorScheme.primary;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: scores.map((e) {
            final score = ((e['score'] as num?) ?? 0).toInt();
            final amount = ((e['count'] as num?) ?? 0).toInt();
            final ratio = maxAmount > 0 ? amount / maxAmount : 0.0;
            final label = (score / 10).toStringAsFixed(0);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 60 * ratio,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.2 + 0.8 * ratio),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _scoreDistributionExpanded = !_scoreDistributionExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Text('SCORE DISTRIBUTION',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.5)),
                  const Spacer(),
                  Icon(_scoreDistributionExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey, size: 18),
                ],
              ),
            ),
          ),
          if (_scoreDistributionExpanded) ...[
            const SizedBox(height: 4),
            const Text('Anime', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            SizedBox(height: 80, child: scoreBar(animeRaw)),
            const SizedBox(height: 16),
            const Text('Manga', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            SizedBox(height: 80, child: scoreBar(mangaRaw)),
            const SizedBox(height: 8),
          ],
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
        ],
      ),
    );
  }

  Widget _buildReleaseYears(Map<String, dynamic>? animeStats) {
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

    final sortedBuckets = buckets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxCount = sortedBuckets.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _releaseYearsExpanded = !_releaseYearsExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Text('TITLES BY ERA',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.5)),
                  const Spacer(),
                  Icon(_releaseYearsExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey, size: 18),
                ],
              ),
            ),
          ),
          if (_releaseYearsExpanded) ...[
            const SizedBox(height: 4),
            Builder(builder: (ctx) {
              final accent = Theme.of(ctx).colorScheme.primary;
              return Column(
                children: sortedBuckets.map((entry) {
                  final label = '${entry.key}–${entry.key + 4}';
                  final count = entry.value;
                  final ratio = maxCount > 0 ? count / maxCount : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 68,
                          child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 6,
                              backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation(accent),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('$count', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  );
                }).toList(),
              );
            }),
            const SizedBox(height: 8),
          ],
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
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
                      ? Center(child: Text('Nobody here yet',
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
