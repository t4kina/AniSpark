import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/anilist_service.dart';

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
                  color: const Color(0xFF13132A),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchStats());
  }

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
    ]);

    if (!mounted) return;
    final statsResult = results[0];
    final followResult = results[1] as Map<String, int>;

    final user = statsResult['user'] as Map<String, dynamic>?;
    setState(() {
      _bannerImage =
          (user?['bannerImage'] as String?) ?? _bannerImage;
      _favoriteAnime =
          (user?['favourites']?['anime']?['nodes'] as List<dynamic>?) ?? [];
      _favoriteCharacters =
          (user?['favourites']?['characters']?['nodes'] as List<dynamic>?) ?? [];
      _followersCount = followResult['followers'] ?? 0;
      _followingCount = followResult['following'] ?? 0;
      _statsLoaded = true;
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
        leading: const SizedBox.shrink(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchStats,
        child: CustomScrollView(
          slivers: [
            // ── Banner + Avatar Header ─────────────────────────────────
            SliverToBoxAdapter(
              child: _buildHeader(avatar, name, context, auth),
            ),

            // ── Stats bar ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF13132A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2A2A4A)),
                  ),
                  child: Column(
                    children: [
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            _statItem('$totalAnime', 'Anime'),
                            _statDividerV(),
                            _statItem(daysWatched, 'Days Watched'),
                            _statDividerV(),
                            _statItem('$chaptersRead', 'Chapters Read'),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFF2A2A4A)),
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            _statItem('$totalManga', 'Manga'),
                            _statDividerV(),
                            _statItem('$_followersCount', 'Followers'),
                            _statDividerV(),
                            _statItem('$_followingCount', 'Following'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            const SliverToBoxAdapter(
              child: Divider(height: 1, color: Color(0xFF1E1E3A)),
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

            // ── Account ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Account',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _settingsTile(
                      context,
                      icon: Icons.open_in_new,
                      label: 'View on AniList',
                      onTap: () {},
                    ),
                    _settingsTile(
                      context,
                      icon: Icons.logout,
                      label: 'Logout',
                      color: Colors.red,
                      onTap: () => _confirmLogout(context, auth),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
      String? avatar, String name, BuildContext context, AuthService auth) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Stack(
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
                  placeholder: (_, _) =>
                      Container(color: const Color(0xFF1E1E3A)),
                  errorWidget: (_, _, _) =>
                      Container(color: const Color(0xFF1E1E3A)),
                )
              : Container(color: const Color(0xFF1E1E3A)),
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
                  const Color(0xFF0E0E2C).withValues(alpha: 0.6),
                  const Color(0xFF0E0E2C),
                ],
                stops: const [0.3, 0.7, 1.0],
              ),
            ),
          ),
        ),
        // Avatar + name, positioned at bottom center
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFF0E0E2C), width: 3),
                ),
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: const Color(0xFF1E1E3A),
                  backgroundImage: avatar != null
                      ? CachedNetworkImageProvider(avatar)
                      : null,
                  child: avatar == null
                      ? const Icon(Icons.person,
                          size: 40, color: Colors.grey)
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ],
          ),
        ),
      ],
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
                      width: 100, height: 140, color: const Color(0xFF1E1E3A)),
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
                      width: 80, height: 80, color: const Color(0xFF1E1E3A)),
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
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 10, letterSpacing: 0.2)),
            ],
          ),
        ),
      );

  Widget _statDividerV() => const VerticalDivider(
        width: 1, thickness: 1, color: Color(0xFF2A2A4A));

  Widget _settingsTile(BuildContext context,
          {required IconData icon,
          required String label,
          Color? color,
          required VoidCallback onTap}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: color ?? Colors.grey),
        title:
            Text(label, style: TextStyle(color: color ?? Colors.white)),
        trailing: const Icon(Icons.chevron_right,
            color: Colors.grey, size: 18),
        onTap: onTap,
      );

  void _confirmLogout(BuildContext context, AuthService auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF13132A),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              auth.logout();
              Navigator.pop(context);
            },
            child: const Text('Logout',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
