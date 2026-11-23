import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/external_url.dart';
import '../providers/settings_provider.dart';
import '../services/anilist_service.dart';
import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../utils/haptics.dart';
import '../utils/score_utils.dart';
import '../utils/translations.dart' show tr, trf;
import '../widgets/app_sheet.dart';
import '../widgets/detail/detail_labels.dart' show GenreChips;
import '../widgets/motion/arrival_builder.dart';
import '../widgets/motion/collapsing_title_bar.dart';
import '../widgets/motion/fade_switcher.dart';
import '../widgets/motion/pressable.dart';
import '../widgets/motion/rounded_hero.dart';
import '../widgets/overlay_button.dart';
import '../widgets/profile/affinity_card.dart';
import '../widgets/profile/favourite_cards.dart';
import '../widgets/profile/profile_card.dart';
import '../widgets/sheet_list_surface.dart';
import '../widgets/skeletons.dart';
import '../widgets/state_message.dart';
import '../widgets/user_avatar.dart';
import 'detail_screen.dart';
import '../widgets/load_error_view.dart';
import '../widgets/app_image.dart';

class UserProfileScreen extends StatefulWidget {
  final int userId;
  final String name;
  final String? avatarUrl;

  /// Tag of the avatar that was tapped to open this page (see
  /// `personHeroTag`), so it flies to the one on the card.
  final String? heroTag;

  /// Talks to AniList; tests pass one with a mock client.
  final AniListService? service;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.heroTag,
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

  /// How many of their latest activities the page shows.
  static const _recentActivityShown = 3;

  // The page swaps its placeholder once the profile and the activity have
  // both answered (or failed), so the activity does not drop in after it.
  bool _profileArrived = false;
  bool _activityArrived = false;
  // ToggleFollow flips whatever AniList has, so the follow button waits for a
  // fresh profile instead of trusting a possibly stale cached isFollowing.
  bool _profileIsFresh = false;
  bool _isFollowing = false;
  bool _isFollower = false;
  bool _togglingFollow = false;
  bool _bioExpanded = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
            _profileArrived = true;
            _loading = !_activityArrived;
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
          if (!mounted) return;
          setState(() {
            _recentActivity = activity;
            _activityArrived = true;
            _loading = !_profileArrived;
          });
        },
      );
    } on Exception catch (e) {
      debugPrint('[UserProfileScreen] Loading activity of ${widget.userId} failed: $e');
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _profileArrived = false;
      _activityArrived = false;
    });
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
          // An avatar flying here lands on the placeholder: it stays until
          // the page has arrived.
          ArrivalBuilder(
            builder: (context, arrived) => FadeSwitcher(
              child: _loading || (!arrived && widget.heroTag != null) ? _buildPlaceholder() : _buildContent(lang),
            ),
          ),
          // Their name, once the one on the card has scrolled away.
          CollapsingTitleBar(
            controller: _scroll,
            title: _profile?['name'] as String? ?? widget.name,
            revealAt: _nameTop - CollapsingTitleBar.height + 12,
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
    showAppSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
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

  /// Room for the back button above the card.
  static const _cardTopGap = 52.0;

  /// About where the name is on the card, below the status bar: under the
  /// gap, the card's padding and the avatar.
  static const _nameTop = _cardTopGap + 122;

  /// The shape of the profile and, when the page was opened from an avatar,
  /// that avatar where the card will have it.
  Widget _buildPlaceholder() {
    const skeleton = ProfileSkeleton(key: ValueKey('uprof-loading'), topGap: _cardTopGap);
    final heroTag = widget.heroTag;
    if (heroTag == null) return skeleton;
    final avatar = ProfileCard.avatarRect(top: MediaQuery.paddingOf(context).top + _cardTopGap);
    return Stack(
      children: [
        skeleton,
        Positioned.fromRect(
          rect: avatar,
          child: RoundedHero(
            tag: heroTag,
            borderRadius: BorderRadius.circular(ProfileCard.avatarSize / 2),
            child: UserAvatar(url: widget.avatarUrl, size: ProfileCard.avatarSize),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(String lang) {
    final p = _profile;
    if (p == null) return LoadErrorView(key: const ValueKey('uprof-error'), onRetry: _retry);

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
    // A glimpse is enough: the latest few that can be shown (AniList also
    // sends kinds the query asks nothing of, as empty entries).
    final recentActivity = [
      for (final activity in _recentActivity)
        if (activity is Map && (activity['type'] == 'TEXT' || activity['media'] != null)) activity,
    ].take(_recentActivityShown).toList();
    final auth = context.watch<AuthService>();
    // Shown from the first frame so the card keeps its height; it only acts
    // once AniList has confirmed the follow state (see [_profileIsFresh]).
    final canFollow = auth.isLoggedIn && auth.user?['id'] != widget.userId;
    final canAct = _profileIsFresh && !_togglingFollow;

    return CustomScrollView(
      key: const ValueKey('uprof-content'),
      controller: _scroll,
      slivers: [
        // ── Who they are and their stats, on their banner ───────────
        SliverToBoxAdapter(
          child: ProfileCard(
            name: name,
            lang: lang,
            avatarUrl: avatar,
            avatarHeroTag: widget.heroTag,
            bannerUrl: banner,
            scrollController: _scroll,
            animeStats: animeStats,
            mangaStats: mangaStats,
            scoreFormat: scoreFormatOf(auth.user),
            nameTag: _isFollower ? tr('uprof_follows_you', lang) : null,
            topGap: _cardTopGap,
            onCountTap: (type) {
              final count = type == 'MANGA' ? totalManga : totalAnime;
              if (count > 0) _showListSheet(context, type);
            },
            // Following them, the Following button opens these same actions.
            cornerButton: canFollow && !_isFollowing
                ? ProfileCard.roundButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: tr('tooltip_more', lang),
                    onPressed: () {
                      if (_profileIsFresh) _showProfileActions(context, lang);
                    },
                  )
                : null,
            actions: [
              if (canFollow)
                _isFollowing
                    ? ProfileCard.secondaryButton(
                        label: '${tr('uprof_following_button', lang)}${_togglingFollow ? '…' : ''}',
                        icon: Icons.check_rounded,
                        trailing: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.white),
                        onPressed: canAct ? () => _showProfileActions(context, lang) : null,
                      )
                    : ProfileCard.primaryButton(
                        label: _togglingFollow ? '…' : tr('uprof_follow', lang),
                        icon: Icons.person_add_alt_1_rounded,
                        onPressed: canAct ? _toggleFollow : null,
                      ),
            ],
          ),
        ),

        // ── Bio ────────────────────────────────────────────────────────
        if (about.isNotEmpty)
          SliverToBoxAdapter(child: _buildBio(about, lang, top: ProfileCard.followingGap)),

        // ── Most watched genres ──────────────────────────────────────────
        if (topGenres.isNotEmpty)
          SliverToBoxAdapter(child: _buildGenreChips(topGenres, lang, top: about.isEmpty ? ProfileCard.followingGap : 24)),

        // ── Favourite Anime ────────────────────────────────────────────
        if (favAnime.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              // Right under the header when nothing comes between.
              padding: EdgeInsets.fromLTRB(
                  16, about.isEmpty && topGenres.isEmpty ? ProfileCard.followingGap : 24, 16, 10),
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

        // ── Affinity with the viewer (hides itself when not applicable) ──
        // Below what the profile itself shows: it answers later, and opening
        // here it does not push the rest of the page down.
        SliverToBoxAdapter(child: AffinityCard(userId: widget.userId, userName: name)),

        // ── Recent activity ────────────────────────────────────────────
        if (recentActivity.isNotEmpty) ...[
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
              (_, i) => _recentActivityRow(recentActivity[i], lang),
              childCount: recentActivity.length,
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildBio(String about, String lang, {double top = 20}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top, 16, 0),
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
              Pressable.dim(
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

  /// The genres this user watches most, each in its own colour, opening
  /// the grid of that genre.
  Widget _buildGenreChips(List<String> genres, String lang, {double top = 24}) => Padding(
        padding: EdgeInsets.fromLTRB(16, top, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                tr('profile_top_genres', lang),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.5),
              ),
            ),
            const SizedBox(height: 10),
            GenreChips(genres: genres, isManga: false),
          ],
        ),
      );

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
      child: Pressable(
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
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: AppImage(url: cover, cacheWidth: 72, width: 36, height: 50),
              ),
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
    showAppSheet<void>(
      context: context,
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
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 1,
      builder: (_, scrollController) => Column(
        children: [
          SheetTitle(tr(isAnime ? 'uprof_anime_list' : 'uprof_manga_list', lang)),
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
                ? const ListSkeleton(coverSize: Size(46, 64))
                : _isPrivate
                ? StateMessage(icon: Icons.lock_outline, message: tr('affinity_private', lang))
                : _hasError
                ? LoadErrorView(onRetry: _retry)
                : TabBarView(
                    controller: _tabs,
                    children: _statuses.map((s) {
                      final entries = _lists?[s] ?? [];
                      if (entries.isEmpty) {
                        return StateMessage(icon: Icons.inbox_outlined, message: tr('nothing_here', lang));
                      }
                      return SheetListSurface(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: entries.length,
                          itemBuilder: (_, i) =>
                              _EntryTile(entry: entries[i], isAnime: isAnime),
                        ),
                      );
                    }).toList(),
                  ),
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

    return Pressable(
      pressedScale: 0.98,
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
              child: AppImage(url: image, cacheWidth: 92, width: 46, height: 64),
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
