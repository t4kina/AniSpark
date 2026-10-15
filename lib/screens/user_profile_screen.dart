import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../utils/external_url.dart';
import '../providers/settings_provider.dart';
import '../services/anilist_service.dart';
import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../utils/haptics.dart';
import '../utils/score_utils.dart';
import '../utils/translations.dart' show tr, trf;
import '../widgets/motion/fade_switcher.dart';
import '../widgets/overlay_button.dart';
import '../widgets/profile/affinity_card.dart';
import '../widgets/profile/favourite_cards.dart';
import '../widgets/profile/profile_card.dart';
import 'detail_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final int userId;
  final String name;
  final String? avatarUrl;

  /// Talks to AniList; tests pass one with a mock client.
  final AniListService? service;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.service,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late final _service = widget.service ?? AniListService();

  Map<String, dynamic>? _profile;
  List<dynamic> _recentActivity = [];
  bool _loading = true;
  // ToggleFollow flips whatever AniList has, so the follow button waits for a
  // fresh profile instead of trusting a possibly stale cached isFollowing.
  bool _profileIsFresh = false;
  bool _isFollowing = false;
  bool _isFollower = false;
  bool _togglingFollow = false;
  bool _bioExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Cache key for data that depends on who is looking (isFollowing etc.).
  String _viewerKey(String name) {
    final viewerId = context.read<AuthService>().user?['id'] as int?;
    final key = '$name:${widget.userId}';
    return viewerId != null ? ApiCache.userKey(viewerId, key) : 'anon:$key';
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final token = auth.isLoggedIn ? auth.token : null;
    final cache = context.read<ApiCache>();
    final profileKey = _viewerKey('profile');
    final activityKey = _viewerKey('activity');
    try {
      await Future.wait([
        _loadProfile(cache, profileKey, token),
        _loadActivity(cache, activityKey, token),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProfile(ApiCache cache, String key, String? token) async {
    try {
      await cache.load<Map<String, dynamic>?>(
        key: key,
        fetch: () => _service.getPublicUserProfile(widget.userId, token: token),
        decode: (json) => (json as Map).cast<String, dynamic>(),
        onData: (data, {required isFresh}) {
          if (!mounted) return;
          setState(() {
            _profile = data;
            _profileIsFresh = isFresh;
            _isFollowing = data?['isFollowing'] == true;
            _isFollower = data?['isFollower'] == true;
            _loading = false;
          });
        },
        isValid: (data) => data != null,
      );
    } on Exception catch (e) {
      debugPrint('[UserProfileScreen] Loading profile ${widget.userId} failed: $e');
    }
  }

  Future<void> _loadActivity(ApiCache cache, String key, String? token) async {
    try {
      await cache.load<List<dynamic>>(
        key: key,
        fetch: () => _service.getUserRecentActivity(widget.userId, token: token),
        decode: (json) => json as List<dynamic>,
        onData: (activity, {required isFresh}) {
          if (mounted) setState(() => _recentActivity = activity);
        },
      );
    } on Exception catch (e) {
      debugPrint('[UserProfileScreen] Loading activity of ${widget.userId} failed: $e');
    }
  }

  void _retry() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _toggleFollow() async {
    final auth = context.read<AuthService>();
    final token = auth.token;
    if (!auth.isLoggedIn || token == null || _togglingFollow) return;
    final cache = context.read<ApiCache>();
    final profileKey = _viewerKey('profile');
    final lang = context.read<SettingsProvider>().language;
    final messenger = ScaffoldMessenger.of(context);
    final wasFollowing = _isFollowing;
    setState(() => _togglingFollow = true);
    bool? result;
    try {
      result = await _service.toggleFollow(widget.userId, token);
    } on Exception catch (e) {
      debugPrint('[UserProfileScreen] Toggling follow failed: $e');
    }
    // toggleFollow also reports an HTTP error as "not following", so an
    // unchanged state means the toggle didn't go through.
    if (result == null || result == wasFollowing) {
      if (!mounted) return;
      setState(() => _togglingFollow = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('save_failed', lang))));
      return;
    }
    final nowFollowing = result;
    if (nowFollowing) lightHaptic();
    final profile = _profile;
    final updated =
        profile == null ? null : {...profile, 'isFollowing': nowFollowing};
    if (mounted) {
      setState(() {
        if (updated != null) _profile = updated;
        _isFollowing = nowFollowing;
        _togglingFollow = false;
      });
    }
    if (updated == null) return;
    try {
      // So the next visit doesn't flash the old follow state.
      await cache.write(profileKey, updated);
    } on Exception catch (e) {
      debugPrint('[UserProfileScreen] Caching the follow state failed: $e');
    }
  }

  Future<void> _openAniListProfile() =>
      openExternalUrl('https://anilist.co/user/${Uri.encodeComponent(widget.name)}');

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;

    return Scaffold(
      body: Stack(
        children: [
          FadeSwitcher(
            child: _loading
                ? KeyedSubtree(key: const ValueKey('uprof-loading'), child: _buildShimmer())
                : _buildContent(lang),
          ),
          // 44px touch target around a 36px circle, so the offset is 4px smaller.
          Positioned(
            top: MediaQuery.of(context).padding.top + 2,
            left: 8,
            child: overlayBtn(
              icon: Icons.arrow_back,
              tooltip: tr('tooltip_back', lang),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Unfollow (when following), block and report; the last two are done
  /// on AniList's site.
  void _showProfileActions(BuildContext context, String lang) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isFollowing)
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
                  title: Text(tr('uprof_unfollow', lang), style: const TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(sheet);
                    _toggleFollow();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: Text(tr('uprof_block', lang)),
                onTap: () {
                  Navigator.pop(sheet);
                  _openAniListProfile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(tr('uprof_report', lang)),
                onTap: () {
                  Navigator.pop(sheet);
                  _openAniListProfile();
                },
              ),
            ],
          ),
        ),
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

  Widget _buildContent(String lang) {
    final p = _profile;
    if (p == null) return _LoadErrorView(key: const ValueKey('uprof-error'), onRetry: _retry);

    final banner = p['bannerImage'] as String?;
    final avatar = p['avatar']?['large'] as String? ?? widget.avatarUrl;
    final name = p['name'] as String? ?? widget.name;
    final animeStats = p['statistics']?['anime'] as Map<String, dynamic>?;
    final mangaStats = p['statistics']?['manga'] as Map<String, dynamic>?;

    final totalAnime = (animeStats?['count'] as num?)?.toInt() ?? 0;
    final totalManga = (mangaStats?['count'] as num?)?.toInt() ?? 0;

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
    final auth = context.watch<AuthService>();
    final canFollow = _profileIsFresh && auth.isLoggedIn && auth.user?['id'] != widget.userId;

    return CustomScrollView(
      key: const ValueKey('uprof-content'),
      slivers: [
        // ── Who they are and their stats, on their banner ───────────
        SliverToBoxAdapter(
          child: ProfileCard(
            name: name,
            lang: lang,
            avatarUrl: avatar,
            bannerUrl: banner,
            animeStats: animeStats,
            mangaStats: mangaStats,
            scoreFormat: scoreFormatOf(auth.user),
            nameTag: _isFollower ? tr('uprof_follows_you', lang) : null,
            // Room for the back button above the card.
            topGap: 52,
            onCountTap: (type) {
              final count = type == 'MANGA' ? totalManga : totalAnime;
              if (count > 0) _showListSheet(context, type);
            },
            cornerButton: canFollow
                ? ProfileCard.roundButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: tr('tooltip_more', lang),
                    onPressed: () => _showProfileActions(context, lang),
                  )
                : null,
            actions: [
              if (canFollow)
                _isFollowing
                    ? ProfileCard.secondaryButton(
                        label: '${tr('uprof_following_button', lang)}${_togglingFollow ? '…' : ''}',
                        icon: Icons.check_rounded,
                        trailing: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.white),
                        onPressed: () => _showProfileActions(context, lang),
                      )
                    : ProfileCard.primaryButton(
                        label: _togglingFollow ? '…' : tr('uprof_follow', lang),
                        icon: Icons.person_add_alt_1_rounded,
                        onPressed: _togglingFollow ? null : _toggleFollow,
                      ),
            ],
          ),
        ),

        // ── Affinity with the viewer (hides itself when not applicable) ──
        SliverToBoxAdapter(child: AffinityCard(userId: widget.userId, userName: name)),

        // ── Bio ────────────────────────────────────────────────────────
        if (about.isNotEmpty)
          SliverToBoxAdapter(child: _buildBio(about, lang)),

        // ── Top genres ─────────────────────────────────────────────────
        if (topGenres.isNotEmpty)
          SliverToBoxAdapter(child: _buildGenreChips(topGenres)),

        // ── Favourite Anime ────────────────────────────────────────────
        if (favAnime.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
              child: Text(tr('favorite_anime', lang),
                  style: const TextStyle(
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
                itemBuilder: (_, i) => FavouriteMediaCard(
                  media: favAnime[i] as Map<String, dynamic>,
                  heroScope: 'uprof-favs-anime',
                ),
              ),
            ),
          ),
        ],

        // ── Favourite Manga ────────────────────────────────────────────
        if (favManga.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Text(tr('uprof_favorite_manga', lang),
                  style: const TextStyle(
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
                itemBuilder: (_, i) => FavouriteMediaCard(
                  media: favManga[i] as Map<String, dynamic>,
                  heroScope: 'uprof-favs-manga',
                ),
              ),
            ),
          ),
        ],

        // ── Favourite Characters ───────────────────────────────────────
        if (favChars.isNotEmpty) ...[
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
            child: SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: favChars.length,
                itemBuilder: (_, i) => FavouriteCharacterCard(
                  character: favChars[i] as Map<String, dynamic>,
                ),
              ),
            ),
          ),
        ],

        // ── Recent activity ────────────────────────────────────────────
        if (_recentActivity.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
              child: Text(tr('uprof_recent_activity', lang),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: Colors.grey, letterSpacing: 0.5)),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _recentActivityRow(_recentActivity[i], lang),
              childCount: _recentActivity.length,
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildBio(String about, String lang) {
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
            Text(tr('uprof_about', lang),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
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
                  tr(_bioExpanded ? 'uprof_show_less' : 'uprof_show_more', lang),
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

  Widget _recentActivityRow(dynamic activity, String lang) {
    final type = activity['type'] as String?;
    final createdAt = activity['createdAt'] as int? ?? 0;
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(createdAt * 1000));
    final timeStr = diff.inMinutes < 60
        ? trf('feed_minutes_ago', lang, {'n': diff.inMinutes})
        : diff.inHours < 24
            ? trf('feed_hours_ago', lang, {'n': diff.inHours})
            : trf('feed_days_ago', lang, {'n': diff.inDays});

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
    final title = context.read<SettingsProvider>().resolveTitle(media?['title'] as Map<String, dynamic>?);
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
  bool _hasError = false;
  bool _isPrivate = false;

  static const _statuses = ['CURRENT', 'COMPLETED', 'DROPPED', 'PAUSED', 'PLANNING'];

  /// Translation key of each status tab, worded like the user's own lists.
  static String _labelKey(String status, {required bool isAnime}) =>
      switch (status) {
        'CURRENT' => isAnime ? 'watching' : 'reading',
        'COMPLETED' => 'completed',
        'DROPPED' => 'dropped',
        'PAUSED' => 'on_hold',
        _ => isAnime ? 'plan_to_watch' : 'plan_to_read',
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
    try {
      final data = await widget.service.getPublicUserList(widget.userId, widget.type);
      if (mounted) setState(() { _lists = data; _loading = false; });
    } on Exception catch (e) {
      // AniList answers 404 for private (or deleted) users.
      final isPrivate = e is AniListRequestException && e.statusCode == 404;
      if (!isPrivate) {
        debugPrint('[UserProfileScreen] Loading ${widget.type} list of ${widget.userId} failed: $e');
      }
      if (mounted) setState(() { _loading = false; _isPrivate = isPrivate; _hasError = !isPrivate; });
    }
  }

  void _retry() {
    setState(() { _loading = true; _hasError = false; });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lang = context.watch<SettingsProvider>().language;
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
                tr(isAnime ? 'uprof_anime_list' : 'uprof_manga_list', lang),
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
                final label = tr(_labelKey(s, isAnime: isAnime), lang);
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
                  : _isPrivate
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 40, color: cs.onSurface.withValues(alpha: 0.4)),
                          const SizedBox(height: 8),
                          Text(tr('affinity_private', lang),
                              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
                        ],
                      ),
                    )
                  : _hasError
                  ? _LoadErrorView(onRetry: _retry)
                  : TabBarView(
                      controller: _tabs,
                      children: _statuses.map((s) {
                        final entries = _lists?[s] ?? [];
                        if (entries.isEmpty) {
                          return Center(
                            child: Text(tr('nothing_here', lang),
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

class _LoadErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _LoadErrorView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
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
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(tr('retry', lang)),
          ),
        ],
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
    final title = context.read<SettingsProvider>().resolveTitle(media['title'] as Map<String, dynamic>?);
    final image = media['coverImage']?['medium'] as String?;
    final progress = (entry['progress'] as num?)?.toInt() ?? 0;
    final score = (entry['score'] as num?)?.toDouble() ?? 0.0;
    final total = isAnime
        ? (media['episodes'] as num?)?.toInt()
        : (media['chapters'] as num?)?.toInt();
    final cs = Theme.of(context).colorScheme;
    final lang = context.watch<SettingsProvider>().language;
    final unit = tr(isAnime ? 'uprof_ep_short' : 'uprof_ch_short', lang);
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
                            ? '$progress / $total $unit'
                            : '$progress $unit',
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
