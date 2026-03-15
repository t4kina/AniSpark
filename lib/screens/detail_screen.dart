import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/anilist_service.dart';
import '../services/auth_service.dart';
import '../providers/anime_list_provider.dart';
import '../models/anime.dart';

class DetailScreen extends StatefulWidget {
  final int animeId;
  const DetailScreen({super.key, required this.animeId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen>
    with TickerProviderStateMixin {
  final _service = AniListService();
  Map<String, dynamic>? _data;
  bool _loading = true;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _service.getAnimeDetail(widget.animeId);
    if (mounted) setState(() { _data = data; _loading = false; });
  }

  // Map local status string → AniList enum
  String _toAniListStatus(String local) => switch (local) {
    'watching'      => 'CURRENT',
    'completed'     => 'COMPLETED',
    'plan_to_watch' => 'PLANNING',
    'dropped'       => 'DROPPED',
    'on_hold'       => 'PAUSED',
    'rewatching'    => 'REPEATING',
    _               => 'PLANNING',
  };

  void _showEditModal(BuildContext context, AnimeListProvider provider) {
    final anime = Anime.fromApi(_data!);
    final existing = provider.isInList(anime.id) ? provider.getAnime(anime.id) : null;
    String selectedStatus = existing?.status ?? 'plan_to_watch';
    int progress = existing?.episodesWatched ?? 0;
    double score = (existing?.userScore ?? 0).toDouble();
    final totalEps = _data!['episodes'] as int?;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2128),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                anime.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),

              // Status
              const Text('Status',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip('Watching', 'watching', selectedStatus,
                      (v) => setModal(() => selectedStatus = v)),
                  _statusChip('Completed', 'completed', selectedStatus,
                      (v) => setModal(() => selectedStatus = v)),
                  _statusChip('Plan to Watch', 'plan_to_watch', selectedStatus,
                      (v) => setModal(() => selectedStatus = v)),
                  _statusChip('On Hold', 'on_hold', selectedStatus,
                      (v) => setModal(() => selectedStatus = v)),
                  _statusChip('Dropped', 'dropped', selectedStatus,
                      (v) => setModal(() => selectedStatus = v)),
                  _statusChip('Rewatching', 'rewatching', selectedStatus,
                      (v) => setModal(() => selectedStatus = v)),
                ],
              ),
              const SizedBox(height: 16),

              // Progress counter
              const Text('Progress',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _counterBtn(Icons.remove, () {
                    if (progress > 0) setModal(() => progress--);
                  }),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      totalEps != null
                          ? '$progress / $totalEps ep'
                          : '$progress ep',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _counterBtn(Icons.add, () {
                    if (totalEps == null || progress < totalEps) {
                      setModal(() => progress++);
                    }
                  }),
                ],
              ),
              const SizedBox(height: 16),

              // Score picker
              const Text('Score (0–10)',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _counterBtn(Icons.remove, () {
                    if (score > 0) setModal(() => score = (score - 0.5).clamp(0, 10));
                  }),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      score == 0 ? '—' : score.toStringAsFixed(1),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _counterBtn(Icons.add, () {
                    if (score < 10) setModal(() => score = (score + 0.5).clamp(0, 10));
                  }),
                ],
              ),
              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF02A9FF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        anime.status = selectedStatus;
                        anime.episodesWatched = progress;
                        anime.userScore = score.round();
                        provider.addAnime(anime);

                        // Sync to AniList if logged in
                        final auth = context.read<AuthService>();
                        if (auth.isLoggedIn) {
                          _service.saveListEntry(
                            mediaId: anime.id,
                            status: _toAniListStatus(selectedStatus),
                            progress: progress,
                            score: score,
                            token: auth.token!,
                          );
                        }

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${anime.title} saved!')),
                        );
                      },
                      child: const Text('Save',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (provider.isInList(widget.animeId)) ...[
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        provider.removeAnime(widget.animeId);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _counterBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF21262D),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      );

  Widget _statusChip(String label, String value, String selected,
      Function(String) onTap) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Chip(
        label: Text(label),
        backgroundColor:
            isSelected ? const Color(0xFF02A9FF) : const Color(0xFF21262D),
        labelStyle: TextStyle(
            color: isSelected ? Colors.white : Colors.grey, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnimeListProvider>();

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_data == null) {
      return const Scaffold(body: Center(child: Text('Failed to load')));
    }

    final title =
        _data!['title']['english'] ?? _data!['title']['romaji'] ?? 'Unknown';
    final cover = _data!['coverImage']?['extraLarge'] ??
        _data!['coverImage']?['large'];
    final banner = _data!['bannerImage'];
    final score = _data!['averageScore'];
    final episodes = _data!['episodes'];
    final status = _data!['status'];
    final format = _data!['format'];
    final source = _data!['source'];
    final genres = (_data!['genres'] as List? ?? []);
    final description = (_data!['description'] ?? '')
        .replaceAll(RegExp(r'<[^>]*>'), '');
    final studios = (_data!['studios']?['nodes'] as List? ?? [])
        .map((s) => s['name'] as String)
        .toList();
    final startDate = _data!['startDate'];
    final nextAiring = _data!['nextAiringEpisode'];
    final characters =
        (_data!['characters']?['edges'] as List? ?? []).cast<Map<String, dynamic>>();
    final staff =
        (_data!['staff']?['edges'] as List? ?? []).cast<Map<String, dynamic>>();

    final inList = provider.isInList(widget.animeId);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (_, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: banner != null
                  ? CachedNetworkImage(imageUrl: banner, fit: BoxFit.cover)
                  : Container(color: const Color(0xFF1C2128)),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  inList ? Icons.bookmark : Icons.bookmark_border,
                  color: const Color(0xFF02A9FF),
                ),
                onPressed: () => _showEditModal(context, provider),
              ),
            ],
          ),
          // Cover + title + quick stats
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cover != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: cover,
                        width: 100,
                        height: 150,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                      ),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (score != null)
                          Row(children: [
                            const Icon(Icons.star,
                                size: 16, color: Color(0xFFFFC107)),
                            const SizedBox(width: 4),
                            Text(
                                '${(score / 10).toStringAsFixed(1)} / 10',
                                style: const TextStyle(color: Colors.grey)),
                          ]),
                        const SizedBox(height: 4),
                        if (format != null)
                          _metaRow(Icons.tv, _formatLabel(format.toString())),
                        if (episodes != null)
                          _metaRow(Icons.format_list_numbered,
                              '$episodes episodes'),
                        if (status != null)
                          _metaRow(Icons.circle,
                              _statusLabel(status.toString()),
                              color: _statusColor(status.toString())),
                        if (startDate?['year'] != null)
                          _metaRow(Icons.calendar_today,
                              _seasonLabel(_data!)),
                        if (nextAiring != null)
                          _metaRow(Icons.schedule,
                              'Ep ${nextAiring['episode']} in ${_airingCountdown(nextAiring['airingAt'] as int)}',
                              color: const Color(0xFF02A9FF)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Pinned TabBar
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Characters'),
                  Tab(text: 'Staff'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            // Overview tab
            _OverviewTab(
              genres: genres.cast<String>(),
              description: description,
              studios: studios,
              source: source?.toString(),
            ),
            // Characters tab
            _CharactersTab(characters: characters),
            // Staff tab
            _StaffTab(staff: staff),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF02A9FF),
        onPressed: () => _showEditModal(context, provider),
        icon: Icon(inList ? Icons.edit : Icons.add),
        label: Text(inList ? 'Edit in List' : 'Add to List'),
      ),
    );
  }

  Widget _metaRow(IconData icon, String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Icon(icon, size: 13, color: color ?? Colors.grey),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    color: color ?? Colors.grey, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  String _formatLabel(String f) => switch (f) {
    'TV'      => 'TV Series',
    'MOVIE'   => 'Movie',
    'OVA'     => 'OVA',
    'ONA'     => 'ONA',
    'SPECIAL' => 'Special',
    'MUSIC'   => 'Music',
    _         => f,
  };

  String _statusLabel(String s) => switch (s) {
    'FINISHED'         => 'Finished',
    'RELEASING'        => 'Airing',
    'NOT_YET_RELEASED' => 'Upcoming',
    'CANCELLED'        => 'Cancelled',
    'HIATUS'           => 'On Hiatus',
    _                  => s,
  };

  Color _statusColor(String s) => switch (s) {
    'RELEASING' => Colors.green,
    'FINISHED'  => Colors.grey,
    'CANCELLED' => Colors.red,
    _           => Colors.orange,
  };

  String _seasonLabel(Map<String, dynamic> data) {
    final sd = data['startDate'];
    final y = sd?['year'];
    if (y == null) return '';
    final m = sd?['month'] as int? ?? 1;
    final season = switch (m) {
      1 || 2 || 3  => 'Winter',
      4 || 5 || 6  => 'Spring',
      7 || 8 || 9  => 'Summer',
      _            => 'Fall',
    };
    return '$season $y';
  }

  String _airingCountdown(int airingAt) {
    final diff = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000)
        .difference(DateTime.now());
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }
}

// ─── Tab bar delegate ──────────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        color: const Color(0xFF0D1117),
        child: tabBar,
      );

  @override
  bool shouldRebuild(_TabBarDelegate old) => old.tabBar != tabBar;
}

// ─── Overview Tab ──────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final List<String> genres;
  final String description;
  final List<String> studios;
  final String? source;

  const _OverviewTab({
    required this.genres,
    required this.description,
    required this.studios,
    this.source,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        // Studios + Source row
        if (studios.isNotEmpty || source != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (studios.isNotEmpty)
                  _infoChip(Icons.business, studios.first),
                if (source != null)
                  _infoChip(Icons.book, _sourceLabel(source!)),
              ],
            ),
          ),
        // Genres
        if (genres.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: genres
                .map((g) => Chip(
                      label: Text(g,
                          style: const TextStyle(fontSize: 11)),
                      backgroundColor: const Color(0xFF21262D),
                      padding: EdgeInsets.zero,
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
        ],
        // Synopsis
        if (description.isNotEmpty) ...[
          const Text('Synopsis',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(description,
              style: const TextStyle(color: Colors.grey, height: 1.6)),
        ],
      ],
    );
  }

  Widget _infoChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.grey),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      );

  String _sourceLabel(String s) => switch (s) {
    'MANGA'        => 'Manga',
    'LIGHT_NOVEL'  => 'Light Novel',
    'VISUAL_NOVEL' => 'Visual Novel',
    'VIDEO_GAME'   => 'Video Game',
    'ORIGINAL'     => 'Original',
    'ANIME'        => 'Anime',
    'NOVEL'        => 'Novel',
    _              => s,
  };
}

// ─── Characters Tab ────────────────────────────────────────────────────────

class _CharactersTab extends StatelessWidget {
  final List<Map<String, dynamic>> characters;
  const _CharactersTab({required this.characters});

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) {
      return const Center(
          child: Text('No character data', style: TextStyle(color: Colors.grey)));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3.0,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: characters.length,
      itemBuilder: (_, i) {
        final edge = characters[i];
        final charNode = edge['node'] as Map<String, dynamic>? ?? {};
        final role = edge['role'] as String? ?? '';
        final charName = charNode['name']?['full'] as String? ?? '';
        final charImg = charNode['image']?['medium'] as String?;
        final vas = edge['voiceActors'] as List? ?? [];
        final va = vas.isNotEmpty ? vas.first as Map<String, dynamic> : null;
        final vaName = va?['name']?['full'] as String? ?? '';
        final vaImg = va?['image']?['medium'] as String?;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Character
              _charAvatar(charImg),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(charName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600)),
                    Text(role.toLowerCase(),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              // Voice actor (right side)
              if (va != null) ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(vaName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                      const Text('JP',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _charAvatar(vaImg),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _charAvatar(String? url) => ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        child: url != null
            ? CachedNetworkImage(
                imageUrl: url,
                width: 42,
                height: 60,
                fit: BoxFit.cover,
                memCacheWidth: 84,
                placeholder: (_, _) =>
                    Container(width: 42, height: 60, color: Colors.grey[800]),
                errorWidget: (_, _, _) =>
                    Container(width: 42, height: 60, color: Colors.grey[800]),
              )
            : Container(width: 42, height: 60, color: Colors.grey[800]),
      );
}

// ─── Staff Tab ─────────────────────────────────────────────────────────────

class _StaffTab extends StatelessWidget {
  final List<Map<String, dynamic>> staff;
  const _StaffTab({required this.staff});

  @override
  Widget build(BuildContext context) {
    if (staff.isEmpty) {
      return const Center(
          child: Text('No staff data', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: staff.length,
      separatorBuilder: (_, _) =>
          const Divider(color: Color(0xFF21262D), height: 1),
      itemBuilder: (_, i) {
        final edge = staff[i];
        final node = edge['node'] as Map<String, dynamic>? ?? {};
        final name = node['name']?['full'] as String? ?? '';
        final role = edge['role'] as String? ?? '';
        final img = node['image']?['medium'] as String?;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF21262D),
            backgroundImage:
                img != null ? CachedNetworkImageProvider(img) : null,
            child: img == null
                ? const Icon(Icons.person, color: Colors.grey)
                : null,
          ),
          title: Text(name,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(role,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        );
      },
    );
  }
}
