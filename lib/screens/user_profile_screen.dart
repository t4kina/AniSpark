import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/anilist_service.dart';

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _service.getPublicUserProfile(widget.userId);
    if (mounted) setState(() { _profile = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading ? _buildShimmer() : _buildContent(),
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
    final favChars = (p['favourites']?['characters']?['nodes'] as List<dynamic>?) ?? [];

    final bg = Theme.of(context).scaffoldBackgroundColor;
    final outline = Theme.of(context).colorScheme.outline;
    final topPadding = MediaQuery.of(context).padding.top;

    return CustomScrollView(
      slivers: [
        // ── Header ────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: ColoredBox(
            color: bg,
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
                              bg.withValues(alpha: 0.6),
                              bg,
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
                // ── Stats card ─────────────────────────────────────────
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
                          child: Row(children: [
                            _stat('$totalAnime', 'Anime'),
                            _vDiv(outline),
                            _stat('$episodesWatched', 'Episodes'),
                            _vDiv(outline),
                            _stat(daysWatched, 'Days Watched'),
                          ]),
                        ),
                        Divider(height: 1, color: outline),
                        IntrinsicHeight(
                          child: Row(children: [
                            _stat('$totalManga', 'Manga'),
                            _vDiv(outline),
                            _stat('$chaptersRead', 'Chapters'),
                            _vDiv(outline),
                            _stat(
                              animeMeanScore > 0
                                  ? animeMeanScore.toStringAsFixed(1)
                                  : '—',
                              'Anime Score',
                            ),
                          ]),
                        ),
                        if (mangaMeanScore > 0) ...[
                          Divider(height: 1, color: outline),
                          IntrinsicHeight(
                            child: Row(children: [
                              _stat(
                                mangaMeanScore.toStringAsFixed(1),
                                'Manga Score',
                              ),
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

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

  Widget _vDiv(Color color) => VerticalDivider(width: 1, thickness: 1, color: color);

  Widget _animeFavCard(dynamic anime) {
    final a = anime as Map<String, dynamic>;
    final image = a['coverImage']?['large'] as String?;
    final title =
        (a['title']?['english'] ?? a['title']?['romaji'] ?? '') as String;
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
    );
  }
}
