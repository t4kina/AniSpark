import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/anilist_service.dart';
import '../services/auth_service.dart';
import '../widgets/overlay_button.dart';
import 'detail_screen.dart';
import 'character_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final int userId;
  final String name;
  final String? avatarUrl;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.name,
    this.avatarUrl,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _service = AniListService();
  Map<String, dynamic>? _profile;
  List<dynamic> _recentActivity = [];
  bool _loading = true;
  bool _isFollowing = false;
  bool _isFollower = false;
  bool _togglingFollow = false;
  bool _bioExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final token = auth.isLoggedIn ? auth.token : null;
    final results = await Future.wait([
      _service.getPublicUserProfile(widget.userId, token: token),
      _service.getUserRecentActivity(widget.userId, token: token),
    ]);
    if (!mounted) return;
    final data = results[0] as Map<String, dynamic>?;
    setState(() {
      _profile = data;
      _recentActivity = results[1] as List<dynamic>;
      _isFollowing = data?['isFollowing'] == true;
      _isFollower = data?['isFollower'] == true;
      _loading = false;
    });
  }

  Future<void> _toggleFollow() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn || _togglingFollow) return;
    setState(() => _togglingFollow = true);
    final nowFollowing = await _service.toggleFollow(widget.userId, auth.token!);
    if (mounted) setState(() { _isFollowing = nowFollowing; _togglingFollow = false; });
  }

  Future<void> _openAniListProfile() async {
    final uri = Uri.parse('https://anilist.co/user/${widget.name}');
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isOwnProfile = auth.isLoggedIn && auth.user?['id'] == widget.userId;

    return Scaffold(
      body: Stack(
        children: [
          _loading ? _buildShimmer() : _buildContent(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            left: 12,
            child: overlayBtn(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (!_loading && auth.isLoggedIn && !isOwnProfile)
            Positioned(
              top: MediaQuery.of(context).padding.top + 6,
              right: 12,
              child: _followButton(context),
            ),
        ],
      ),
    );
  }

  Widget _followButton(BuildContext context) {
    if (_isFollowing) {
      return PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        offset: const Offset(0, 44),
        onSelected: (val) {
          if (val == 'unfollow') _toggleFollow();
          if (val == 'block' || val == 'report') _openAniListProfile();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'unfollow',
            child: Row(children: [
              Icon(Icons.person_remove_outlined, size: 16, color: Colors.red),
              SizedBox(width: 10),
              Text('Unfollow', style: TextStyle(color: Colors.red, fontSize: 13)),
            ]),
          ),
          const PopupMenuItem(
            value: 'block',
            child: Row(children: [
              Icon(Icons.block_outlined, size: 16, color: Colors.grey),
              SizedBox(width: 10),
              Text('Block', style: TextStyle(fontSize: 13)),
            ]),
          ),
          const PopupMenuItem(
            value: 'report',
            child: Row(children: [
              Icon(Icons.flag_outlined, size: 16, color: Colors.grey),
              SizedBox(width: 10),
              Text('Report', style: TextStyle(fontSize: 13)),
            ]),
          ),
        ],
        child: _pillBtn(
          label: _togglingFollow ? 'Following…' : 'Following',
          icon: Icons.check,
          filled: true,
          trailing: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTap: _toggleFollow,
      child: _pillBtn(
        label: _togglingFollow ? '…' : 'Follow',
        icon: Icons.person_add_outlined,
        filled: false,
      ),
    );
  }

  Widget _pillBtn({
    required String label,
    required IconData icon,
    required bool filled,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: filled ? cs.primary : Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: filled ? null : Border.all(color: Colors.white.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          if (trailing != null) ...[const SizedBox(width: 2), trailing],
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Column(
      children: [
        Container(
          height: 200 + topPadding,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final p = _profile;
    if (p == null) {
      return const Center(child: Text('Could not load profile.'));
    }

    final banner = p['bannerImage'] as String?;
    final avatar = p['avatar']?['large'] as String? ?? widget.avatarUrl;
    final name = p['name'] as String? ?? widget.name;
    final animeStats = p['statistics']?['anime'] as Map<String, dynamic>?;
    final mangaStats = p['statistics']?['manga'] as Map<String, dynamic>?;

    final totalAnime = (animeStats?['count'] as num?)?.toInt() ?? 0;
    final episodesWatched = (animeStats?['episodesWatched'] as num?)?.toInt() ?? 0;
    final minutesWatched = (animeStats?['minutesWatched'] as num?)?.toInt() ?? 0;
    final daysWatched = (minutesWatched / 1440).toStringAsFixed(1);
    final animeMeanScore = (animeStats?['meanScore'] as num?)?.toDouble() ?? 0.0;
    final totalManga = (mangaStats?['count'] as num?)?.toInt() ?? 0;
    final chaptersRead = (mangaStats?['chaptersRead'] as num?)?.toInt() ?? 0;
    final mangaMeanScore = (mangaStats?['meanScore'] as num?)?.toDouble() ?? 0.0;

    final favAnime = (p['favourites']?['anime']?['nodes'] as List<dynamic>?) ?? [];
    final favManga = (p['favourites']?['manga']?['nodes'] as List<dynamic>?) ?? [];
    final favChars = (p['favourites']?['characters']?['nodes'] as List<dynamic>?) ?? [];

    final rawGenres = (p['statistics']?['anime']?['genres'] as List<dynamic>?) ?? [];
    final topGenres = (rawGenres.cast<Map<String, dynamic>>().toList()
          ..sort((a, b) => ((b['count'] as num?) ?? 0).compareTo((a['count'] as num?) ?? 0)))
        .take(5)
        .map((g) => g['genre'] as String? ?? '')
        .where((g) => g.isNotEmpty)
        .toList();

    final about = (p['about'] as String? ?? '').trim();

    final surface = Theme.of(context).colorScheme.surface;
    final outline = Theme.of(context).colorScheme.outline;
    final topPadding = MediaQuery.of(context).padding.top;

    return CustomScrollView(
      slivers: [
        // ── Header card ───────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
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
              children: [
                Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    SizedBox(
                      height: 200 + topPadding,
                      width: double.infinity,
                      child: banner != null
                          ? CachedNetworkImage(
                              imageUrl: banner,
                              fit: BoxFit.cover,
                              memCacheWidth: 800,
                              placeholder: (ctx, _) => Container(
                                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest),
                              errorWidget: (_, _, _) => Container(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest),
                            )
                          : Container(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest),
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
                          if (_isFollower) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Follows You',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
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
                          child: Row(children: [
                            _tappableStat('$totalAnime', 'Anime', totalAnime > 0
                                ? () => _showListSheet(context, 'ANIME') : null),
                            _vDiv(outline),
                            _stat('$episodesWatched', 'Episodes'),
                            _vDiv(outline),
                            _stat(daysWatched, 'Days Watched'),
                          ]),
                        ),
                        Divider(height: 1, color: outline),
                        IntrinsicHeight(
                          child: Row(children: [
                            _tappableStat('$totalManga', 'Manga', totalManga > 0
                                ? () => _showListSheet(context, 'MANGA') : null),
                            _vDiv(outline),
                            _stat('$chaptersRead', 'Chapters'),
                            _vDiv(outline),
                            _combinedScore(
                              animeMeanScore > 0 ? animeMeanScore.toStringAsFixed(1) : '—',
                              mangaMeanScore > 0 ? mangaMeanScore.toStringAsFixed(1) : '—',
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Bio ────────────────────────────────────────────────────────
        if (about.isNotEmpty)
          SliverToBoxAdapter(child: _buildBio(about)),

        // ── Top genres ─────────────────────────────────────────────────
        if (topGenres.isNotEmpty)
          SliverToBoxAdapter(child: _buildGenreChips(topGenres)),

        // ── Recent activity ────────────────────────────────────────────
        if (_recentActivity.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
              child: const Text('RECENT ACTIVITY',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: Colors.grey, letterSpacing: 0.5)),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _recentActivityRow(_recentActivity[i]),
              childCount: _recentActivity.length,
            ),
          ),
        ],

        // ── Favourite Anime ────────────────────────────────────────────
        if (favAnime.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
              child: const Text('FAVOURITE ANIME',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                      letterSpacing: 0.5)),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 170,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: favAnime.length,
                itemBuilder: (_, i) => _animeFavCard(favAnime[i]),
              ),
            ),
          ),
        ],

        // ── Favourite Manga ────────────────────────────────────────────
        if (favManga.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: const Text('FAVOURITE MANGA',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                      letterSpacing: 0.5)),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 170,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: favManga.length,
                itemBuilder: (_, i) => _animeFavCard(favManga[i]),
              ),
            ),
          ),
        ],

        // ── Favourite Characters ───────────────────────────────────────
        if (favChars.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: const Text('FAVOURITE CHARACTERS',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                      letterSpacing: 0.5)),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: favChars.length,
                itemBuilder: (_, i) => _charFavCard(favChars[i]),
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildBio(String about) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ABOUT',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: Colors.grey, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _bioExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Text(about,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.5)),
              secondChild: Text(about,
                  style: const TextStyle(fontSize: 13, height: 1.5)),
            ),
            if (about.length > 120) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => setState(() => _bioExpanded = !_bioExpanded),
                child: Text(
                  _bioExpanded ? 'Show less' : 'Show more',
                  style: TextStyle(fontSize: 12, color: cs.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGenreChips(List<String> genres) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: genres.map((g) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
          ),
          child: Text(g,
              style: TextStyle(fontSize: 12, color: cs.primary,
                  fontWeight: FontWeight.w500)),
        )).toList(),
      ),
    );
  }

  Widget _recentActivityRow(dynamic activity) {
    final type = activity['type'] as String?;
    final createdAt = activity['createdAt'] as int? ?? 0;
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(createdAt * 1000));
    final timeStr = diff.inMinutes < 60
        ? '${diff.inMinutes}m ago'
        : diff.inHours < 24
            ? '${diff.inHours}h ago'
            : '${diff.inDays}d ago';

    if (type == 'TEXT') {
      final text = activity['text'] as String? ?? '';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.grey),
              const SizedBox(width: 10),
              Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey))),
              const SizedBox(width: 8),
              Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final media = activity['media'] as Map<String, dynamic>?;
    final status = activity['status'] as String? ?? '';
    final progress = activity['progress'];
    final cover = media?['coverImage']?['medium'] as String?;
    final title = (media?['title']?['english'] ?? media?['title']?['romaji'] ?? '') as String;
    final mediaId = media?['id'] as int?;
    final isAnime = media?['type'] == 'ANIME';
    final actionText = progress != null ? '$status $progress' : status;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GestureDetector(
        onTap: mediaId != null && isAnime
            ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => DetailScreen(animeId: mediaId)))
            : null,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              if (cover != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: CachedNetworkImage(
                    imageUrl: cover, width: 36, height: 50,
                    fit: BoxFit.cover, memCacheWidth: 72,
                  ),
                )
              else
                Container(width: 36, height: 50,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(5),
                    )),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(actionText,
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 10, letterSpacing: 0.2)),
            ],
          ),
        ),
      );

  Widget _tappableStat(String value, String label, VoidCallback? onTap) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        child: GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(value,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: cs.primary)),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 10, letterSpacing: 0.2)),
                        const SizedBox(width: 3),
                        Icon(Icons.chevron_right_rounded, size: 12, color: Colors.grey.withValues(alpha: 0.7)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _combinedScore(String animeScore, String mangaScore) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(animeScore,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: const Text('Anime Score',
                          style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 0.2)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('|',
                    style: TextStyle(
                        color: Colors.grey.withValues(alpha: 0.4), fontSize: 16)),
              ),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(mangaScore,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: const Text('Manga Score',
                          style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 0.2)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _vDiv(Color color) => VerticalDivider(width: 1, thickness: 1, color: color);

  void _showListSheet(BuildContext context, String type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserListSheet(
        userId: widget.userId,
        type: type,
        service: _service,
      ),
    );
  }

  Widget _animeFavCard(dynamic anime) {
    final a = anime as Map<String, dynamic>;
    final id = a['id'] as int?;
    final image = a['coverImage']?['large'] as String?;
    final title =
        (a['title']?['english'] ?? a['title']?['romaji'] ?? '') as String;
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
                        width: 100,
                        height: 140,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest),
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
                        width: 80,
                        height: 80,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest),
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
}

// ── Bottom sheet: user anime/manga list ───────────────────────────────────────

class _UserListSheet extends StatefulWidget {
  final int userId;
  final String type;
  final AniListService service;

  const _UserListSheet({
    required this.userId,
    required this.type,
    required this.service,
  });

  @override
  State<_UserListSheet> createState() => _UserListSheetState();
}

class _UserListSheetState extends State<_UserListSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, List<dynamic>>? _lists;
  bool _loading = true;

  static const _statuses = ['CURRENT', 'COMPLETED', 'DROPPED', 'PAUSED', 'PLANNING'];
  static const _labels = {
    'CURRENT': 'Watching',
    'COMPLETED': 'Completed',
    'DROPPED': 'Dropped',
    'PAUSED': 'Paused',
    'PLANNING': 'Planning',
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _statuses.length, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await widget.service.getPublicUserList(widget.userId, widget.type);
    if (mounted) setState(() { _lists = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAnime = widget.type == 'ANIME';

    if (_loading || _lists == null) {
      // Jump to the first tab that has content once loaded
    } else {
      final firstWithContent = _statuses.indexWhere(
          (s) => (_lists![s]?.isNotEmpty ?? false));
      if (firstWithContent >= 0 && _tabs.index == 0 && firstWithContent != 0) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) { if (mounted) _tabs.animateTo(firstWithContent); });
      }
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
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
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                isAnime ? 'Anime List' : 'Manga List',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            // Tabs
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: cs.outlineVariant,
              indicatorColor: cs.primary,
              labelColor: cs.primary,
              unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: _statuses.map((s) {
                final count = _lists?[s]?.length ?? 0;
                final label = isAnime && s == 'CURRENT'
                    ? 'Watching'
                    : !isAnime && s == 'CURRENT'
                        ? 'Reading'
                        : _labels[s]!;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label),
                      if (!_loading && count > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$count',
                              style: TextStyle(fontSize: 10, color: cs.primary,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabs,
                      children: _statuses.map((s) {
                        final entries = _lists?[s] ?? [];
                        if (entries.isEmpty) {
                          return Center(
                            child: Text('Nothing here',
                                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4))),
                          );
                        }
                        return ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: entries.length,
                          itemBuilder: (_, i) =>
                              _EntryTile(entry: entries[i], isAnime: isAnime),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool isAnime;

  const _EntryTile({required this.entry, required this.isAnime});

  @override
  Widget build(BuildContext context) {
    final media = entry['media'] as Map<String, dynamic>? ?? {};
    final id = media['id'] as int?;
    final title = (media['title']?['english'] ?? media['title']?['romaji'] ?? '') as String;
    final image = media['coverImage']?['medium'] as String?;
    final progress = (entry['progress'] as num?)?.toInt() ?? 0;
    final score = (entry['score'] as num?)?.toDouble() ?? 0.0;
    final total = isAnime
        ? (media['episodes'] as num?)?.toInt()
        : (media['chapters'] as num?)?.toInt();
    final cs = Theme.of(context).colorScheme;
    final progressFraction = (total != null && total > 0) ? (progress / total).clamp(0.0, 1.0) : null;

    return GestureDetector(
      onTap: id != null
          ? () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => DetailScreen(animeId: id)))
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: image != null
                  ? CachedNetworkImage(
                      imageUrl: image, width: 46, height: 64,
                      fit: BoxFit.cover, memCacheWidth: 92)
                  : Container(width: 46, height: 64,
                      color: cs.surfaceContainerHighest),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  // Progress bar
                  if (progressFraction != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progressFraction,
                        minHeight: 3,
                        backgroundColor: cs.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(cs.primary),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    children: [
                      Text(
                        total != null
                            ? '$progress / $total ${isAnime ? 'ep' : 'ch'}'
                            : '$progress ${isAnime ? 'ep' : 'ch'}',
                        style: TextStyle(fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Score
            if (score > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  score % 1 == 0 ? score.toInt().toString() : score.toStringAsFixed(1),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                      color: cs.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
