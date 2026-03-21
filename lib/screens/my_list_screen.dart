import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/anilist_service.dart';
import '../services/auth_service.dart';
import '../screens/detail_screen.dart';

enum _SortMode { lastUpdated, alphabetical, ratingHigh, ratingLow }

// ─── Standalone Anime List Screen ──────────────────────────────────────────

class AnimeListScreen extends StatelessWidget {
  const AnimeListScreen({super.key});

  @override
  Widget build(BuildContext context) => _ListTabScreen(type: 'ANIME');
}

// ─── Standalone Manga List Screen ──────────────────────────────────────────

class MangaListScreen extends StatelessWidget {
  const MangaListScreen({super.key});

  @override
  Widget build(BuildContext context) => _ListTabScreen(type: 'MANGA');
}

// ─── Shared wrapper screen ─────────────────────────────────────────────────

class _ListTabScreen extends StatefulWidget {
  final String type;
  const _ListTabScreen({required this.type});

  @override
  State<_ListTabScreen> createState() => _ListTabScreenState();
}

class _ListTabScreenState extends State<_ListTabScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.lastUpdated;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final avatar = auth.user?['avatar']?['large'] as String?;
    final title = widget.type == 'ANIME' ? 'Anime' : 'Manga';

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: ClipOval(
                child: avatar != null
                    ? CachedNetworkImage(
                        imageUrl: avatar,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        memCacheWidth: 64,
                      )
                    : Container(
                        color: const Color(0xFF1E1E3A),
                        child: const Icon(Icons.person, size: 16, color: Colors.grey),
                      ),
              ),
            ),
          ),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.swap_vert, color: Colors.grey),
            color: const Color(0xFF13132A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (_) => [
              _sortItem(_SortMode.lastUpdated, 'Last Updated', Icons.history),
              _sortItem(_SortMode.alphabetical, 'Alphabetical (A–Z)', Icons.sort_by_alpha),
              _sortItem(_SortMode.ratingHigh, 'Rating (Highest)', Icons.star),
              _sortItem(_SortMode.ratingLow, 'Rating (Lowest)', Icons.star_outline),
            ],
          ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Filter by name',
                prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        }),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: _MediaList(
              type: widget.type,
              searchQuery: _searchQuery,
              sortMode: _sortMode,
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_SortMode> _sortItem(_SortMode mode, String label, IconData icon) =>
      PopupMenuItem(
        value: mode,
        child: Row(
          children: [
            Icon(icon, size: 16,
                color: _sortMode == mode ? const Color(0xFF02A9FF) : Colors.grey),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: _sortMode == mode ? const Color(0xFF02A9FF) : Colors.white,
                    fontSize: 13)),
          ],
        ),
      );
}

// ─── Media List (content) ──────────────────────────────────────────────────

class _MediaList extends StatefulWidget {
  final String type;
  final String searchQuery;
  final _SortMode sortMode;
  const _MediaList({required this.type, this.searchQuery = '', this.sortMode = _SortMode.lastUpdated});

  @override
  State<_MediaList> createState() => _MediaListState();
}

class _MediaListState extends State<_MediaList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _service = AniListService();
  Map<String, List<Map<String, dynamic>>> _lists = {};
  bool _loading = true;
  String? _error;
  final Set<String> _collapsedSections = {};

  final _statusOrder = [
    'CURRENT',
    'COMPLETED',
    'PAUSED',
    'DROPPED',
    'PLANNING',
    'REPEATING',
  ];

  final _animeStatusLabels = {
    'CURRENT': 'Watching',
    'COMPLETED': 'Completed',
    'PAUSED': 'On Hold',
    'DROPPED': 'Dropped',
    'PLANNING': 'Plan to Watch',
    'REPEATING': 'Rewatching',
  };

  final _mangaStatusLabels = {
    'CURRENT': 'Reading',
    'COMPLETED': 'Completed',
    'PAUSED': 'On Hold',
    'DROPPED': 'Dropped',
    'PLANNING': 'Plan to Read',
    'REPEATING': 'Rereading',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = 'Login to see your list';
      });
      return;
    }

    final userId = auth.user?['id'];
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'Could not get user ID';
      });
      return;
    }

    try {
      final raw = widget.type == 'ANIME'
          ? await _service.getUserAnimeList(userId, auth.token!)
          : await _service.getUserMangaList(userId, auth.token!);
      final typed = raw.map(
        (k, v) => MapEntry(k, v.cast<Map<String, dynamic>>()),
      );
      setState(() {
        _lists = typed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> _filterEntries(
      List<Map<String, dynamic>> entries) {
    var result = entries.where((e) {
      if (widget.searchQuery.isEmpty) return true;
      final media = e['media'] as Map<String, dynamic>? ?? {};
      final title = (media['title']?['english'] ??
          media['title']?['romaji'] ??
          '') as String;
      return title.toLowerCase().contains(widget.searchQuery.toLowerCase());
    }).toList();

    switch (widget.sortMode) {
      case _SortMode.alphabetical:
        result.sort((a, b) {
          final ta = ((a['media']?['title']?['english'] ?? a['media']?['title']?['romaji'] ?? '') as String).toLowerCase();
          final tb = ((b['media']?['title']?['english'] ?? b['media']?['title']?['romaji'] ?? '') as String).toLowerCase();
          return ta.compareTo(tb);
        });
      case _SortMode.ratingHigh:
        result.sort((a, b) => ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0));
      case _SortMode.ratingLow:
        result.sort((a, b) => ((a['score'] as num?) ?? 0).compareTo((b['score'] as num?) ?? 0));
      case _SortMode.lastUpdated:
        break;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.grey)),
            if (_error == 'Login to see your list')
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF02A9FF)),
                  onPressed: () async {
                    final auth = context.read<AuthService>();
                    try {
                      await auth.login();
                    } catch (_) {}
                  },
                  child: const Text('Login with AniList',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
          ],
        ),
      );
    }
    if (_lists.isEmpty) {
      return const Center(child: Text('Nothing here yet'));
    }

    final labels =
        widget.type == 'ANIME' ? _animeStatusLabels : _mangaStatusLabels;

    // Build a flat item list: headers + entries (only when expanded)
    final items = <({bool isHeader, String? status, String? label, int? count, Map<String, dynamic>? entry})>[];
    for (final status in _statusOrder) {
      final raw = _lists[status];
      if (raw == null || raw.isEmpty) continue;
      final filtered = _filterEntries(raw);
      if (filtered.isEmpty) continue;
      items.add((isHeader: true, status: status, label: labels[status] ?? status, count: filtered.length, entry: null));
      if (!_collapsedSections.contains(status)) {
        for (final e in filtered) {
          items.add((isHeader: false, status: null, label: null, count: null, entry: e));
        }
        items.add((isHeader: false, status: null, label: null, count: null, entry: null)); // spacer
      }
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          if (item.isHeader) {
            final collapsed = _collapsedSections.contains(item.status);
            return InkWell(
              onTap: () => setState(() {
                if (collapsed) {
                  _collapsedSections.remove(item.status);
                } else {
                  _collapsedSections.add(item.status!);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Text(item.label!,
                        style: const TextStyle(fontSize: 15, color: Colors.grey)),
                    const Spacer(),
                    Text('${item.count}',
                        style: const TextStyle(fontSize: 15, color: Colors.grey)),
                    const SizedBox(width: 6),
                    Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ],
                ),
              ),
            );
          }
          if (item.entry == null) return const SizedBox(height: 4);
          return _ListRow(entry: item.entry!, type: widget.type);
        },
      ),
    );
  }
}

// ─── List Row ──────────────────────────────────────────────────────────────

class _ListRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String type;
  const _ListRow({required this.entry, required this.type});

  String _timeUntilAiring(int seconds) {
    final days = seconds ~/ 86400;
    if (days > 0) return '$days day${days == 1 ? '' : 's'}';
    final hours = seconds ~/ 3600;
    return '$hours hour${hours == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final media = entry['media'] as Map<String, dynamic>? ?? {};
    final progress = (entry['progress'] as num?)?.toInt() ?? 0;
    final score = (entry['score'] as num?)?.toDouble() ?? 0;
    final title = (media['title']?['english'] ??
        media['title']?['romaji'] ??
        'Unknown') as String;
    final image = media['coverImage']?['large'] as String?;
    final total = type == 'ANIME'
        ? media['episodes'] as int?
        : media['chapters'] as int?;
    final id = media['id'] as int?;
    final nextAiring = media['nextAiringEpisode'] as Map<String, dynamic>?;

    return InkWell(
      onTap: id != null
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => DetailScreen(animeId: id)),
              )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: image != null
                  ? CachedNetworkImage(
                      imageUrl: image,
                      width: 80,
                      height: 115,
                      fit: BoxFit.cover,
                      memCacheWidth: 160,
                      placeholder: (_, _) => Container(
                          width: 80,
                          height: 115,
                          color: const Color(0xFF1E1E3A)),
                      errorWidget: (_, _, _) => Container(
                          width: 80,
                          height: 115,
                          color: const Color(0xFF1E1E3A)),
                    )
                  : Container(
                      width: 80,
                      height: 115,
                      color: const Color(0xFF1E1E3A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$progress${total != null ? ' / $total' : ''} ${type == 'ANIME' ? 'episodes' : 'chapters'}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey),
                  ),
                  if (score > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star,
                            size: 13, color: Color(0xFFFFC107)),
                        const SizedBox(width: 3),
                        Text(
                          score.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                  if (nextAiring != null) ...[
                    const SizedBox(height: 6),
                    Builder(builder: (_) {
                      final nextEp = nextAiring['episode'] as int;
                      final behindBy = (nextEp - 1) - progress;
                      final color = behindBy >= 1
                          ? const Color(0xFFFFC107)
                          : const Color(0xFF4CAF50);
                      return Row(
                        children: [
                          const Text('ﾒ', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Episode $nextEp airs in ${_timeUntilAiring((nextAiring['timeUntilAiring'] as num).toInt())}',
                              style: TextStyle(fontSize: 12, color: color),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Legacy MyListScreen (kept for backward compat) ────────────────────────

class MyListScreen extends StatelessWidget {
  const MyListScreen({super.key});

  @override
  Widget build(BuildContext context) => const AnimeListScreen();
}
