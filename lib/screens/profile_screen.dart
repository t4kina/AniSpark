import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/anilist_service.dart';
import '../utils/refresh_notifier.dart';
import 'settings_screen.dart';
import 'user_profile_screen.dart';

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
                child: const Icon(Icons.person,
                    size: 50, color: Color(0xFF02A9FF)),
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
                    backgroundColor: const Color(0xFF02A9FF),
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
    final user = auth.user!;
    final animeStats =
        user['statistics']?['anime'] as Map<String, dynamic>?;
    final mangaStats =
        user['statistics']?['manga'] as Map<String, dynamic>?;
    final avatar = user['avatar']?['large'] as String?;
    final name = user['name'] as String? ?? 'Unknown';

    final minutesWatched =
        (animeStats?['minutesWatched'] as num?)?.toInt() ?? 0;
    final daysWatched = (minutesWatched / 1440).toStringAsFixed(1);
    final chaptersRead =
        (mangaStats?['chaptersRead'] as num?)?.toInt() ?? 0;
    final totalAnime = (animeStats?['count'] as num?)?.toInt() ?? 0;
    final totalManga = (mangaStats?['count'] as num?)?.toInt() ?? 0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const SizedBox.shrink(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchStats,
        child: CustomScrollView(
          slivers: [
            // ── Banner + Avatar Header + Stats bar (single sliver to avoid seam) ──
            SliverToBoxAdapter(
              child: _buildHeaderAndStats(
                avatar, name, context,
                totalAnime: totalAnime,
                daysWatched: daysWatched,
                totalManga: totalManga,
                chaptersRead: chaptersRead,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
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

            // ── Following ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                child: const Text('FOLLOWING',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        letterSpacing: 0.5)),
              ),
            ),
            SliverToBoxAdapter(
              child: _following.isEmpty && _statsLoaded
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Not following anyone yet',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    )
                  : SizedBox(
                      height: 90,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _following.length,
                        itemBuilder: (_, i) => _followingCard(_following[i]),
                      ),
                    ),
            ),

            // ── Activity Graph ──────────────────────────────────────────
            SliverToBoxAdapter(child: _buildActivityGraph()),

            // ── Top Genres ─────────────────────────────────────────────
            SliverToBoxAdapter(child: _buildTopGenres(animeStats)),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderAndStats(
    String? avatar,
    String name,
    BuildContext context, {
    required int totalAnime,
    required String daysWatched,
    required int totalManga,
    required int chaptersRead,
  }) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final outline = Theme.of(context).colorScheme.outline;
    return ColoredBox(
      color: bg,
      child: Column(
        children: [
          // ── Banner + Avatar + Name ──────────────────────────────────
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Banner image
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
              // Gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        bg.withValues(alpha: 0.6),
                        bg,
                      ],
                      stops: const [0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
              // Avatar + name
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: bg, width: 3),
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
          // ── Stats card (same widget, no sliver boundary) ───────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
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
                        _statItem(daysWatched, 'Days Watched'),
                        _statDividerV(outline),
                        _statItem('$totalManga', 'Manga'),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: outline),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        _statItem('$chaptersRead', 'Chapters Read'),
                        _statDividerV(outline),
                        _statItem('$_followersCount', 'Followers'),
                        _statDividerV(outline),
                        _statItem('$_followingCount', 'Following'),
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
    final image = a['coverImage']?['large'] as String?;
    final title = (a['title']?['english'] ?? a['title']?['romaji'] ?? '') as String;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
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
    );
  }

  Widget _charFavCard(dynamic char) {
    final c = char as Map<String, dynamic>;
    final image = c['image']?['medium'] as String?;
    final name = c['name']?['full'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(right: 10),
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

  Widget _followingCard(dynamic u) {
    final user = u as Map<String, dynamic>;
    final id = user['id'] as int;
    final name = user['name'] as String? ?? '';
    final avatar = user['avatar']?['large'] as String?;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserProfileScreen(userId: id, name: name, avatarUrl: avatar),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
              child: avatar == null ? const Icon(Icons.person, color: Colors.grey) : null,
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 64,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
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
      if (count == 0) return Theme.of(ctx).colorScheme.surfaceContainerHighest;
      if (maxCount == 0) return const Color(0xFF02A9FF);
      final ratio = count / maxCount;
      if (ratio < 0.25) return const Color(0xFF02A9FF).withValues(alpha: 0.25);
      if (ratio < 0.50) return const Color(0xFF02A9FF).withValues(alpha: 0.50);
      if (ratio < 0.75) return const Color(0xFF02A9FF).withValues(alpha: 0.75);
      return const Color(0xFF02A9FF);
    }

    const cellSize = 10.0;
    const gap = 3.0;
    const step = cellSize + gap;

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
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
            );
          }),
          const SizedBox(height: 6),
          Builder(builder: (ctx) => Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Less', style: TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(width: 4),
              ...List.generate(5, (i) {
                final colors = [
                  Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  const Color(0xFF02A9FF).withValues(alpha: 0.25),
                  const Color(0xFF02A9FF).withValues(alpha: 0.50),
                  const Color(0xFF02A9FF).withValues(alpha: 0.75),
                  const Color(0xFF02A9FF),
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

  Widget _buildTopGenres(Map<String, dynamic>? animeStats) {
    final raw = animeStats?['genres'] as List<dynamic>?;
    if (raw == null || raw.isEmpty) return const SizedBox.shrink();

    final genres = raw
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) =>
          ((b['count'] as num?) ?? 0).compareTo((a['count'] as num?) ?? 0));
    final top = genres.take(5).toList();
    final maxCount = (top.first['count'] as num).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TOP GENRES',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 0.5)),
          const SizedBox(height: 12),
          ...top.map((g) {
            final genre = g['genre'] as String? ?? '';
            final count = (g['count'] as num?)?.toInt() ?? 0;
            final score = (g['meanScore'] as num?)?.toDouble() ?? 0.0;
            final ratio = maxCount > 0 ? count / maxCount : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Builder(builder: (ctx) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(genre,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(
                          '$count anime${score > 0 ? '  ·  ${score.toStringAsFixed(1)} ★' : ''}',
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
                        backgroundColor:
                            Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF02A9FF)),
                      ),
                    ),
                  ],
                );
              }),
            );
          }),
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
