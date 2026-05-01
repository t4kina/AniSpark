import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/anilist_service.dart';
import '../services/auth_service.dart';
import '../screens/detail_screen.dart';
import '../main.dart';
import '../providers/settings_provider.dart';
import '../utils/translations.dart' show tr;
import '../utils/refresh_notifier.dart';
import '../services/notification_service.dart';

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
  Set<String> _activeGenres = {};

  static const _genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy', 'Horror',
    'Mahou Shoujo', 'Mecha', 'Music', 'Mystery', 'Psychological', 'Romance',
    'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural', 'Thriller',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showGenreFilter(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Filter by Genre',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  const Spacer(),
                  if (_activeGenres.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(() => _activeGenres = {});
                        setSheet(() {});
                      },
                      child: const Text('Clear', style: TextStyle(fontSize: 13)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _genres.map((g) {
                  final selected = _activeGenres.contains(g);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _activeGenres.remove(g);
                        } else {
                          _activeGenres.add(g);
                        }
                      });
                      setSheet(() {});
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? cs.primary : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? cs.primary : cs.outline.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        g,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          color: selected ? Colors.white : cs.onSurface,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final avatar = auth.user?['avatar']?['large'] as String?;
    final title = widget.type == 'ANIME' ? tr('nav_anime', lang) : tr('nav_manga', lang);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: GestureDetector(
          onTap: () => MainNavigation.navigateToTab(4),
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
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
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person, size: 16, color: Colors.grey),
                        ),
                ),
              ),
            ),
          ),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: Icon(
              Icons.tune_rounded,
              size: 22,
              color: _activeGenres.isNotEmpty ? const Color(0xFF02A9FF) : Colors.grey,
            ),
            onPressed: () => _showGenreFilter(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: PopupMenuButton<_SortMode>(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.swap_vert, color: Colors.grey, size: 22),
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (_) => [
              _sortItem(_SortMode.lastUpdated, tr('last_updated', lang), Icons.history),
              _sortItem(_SortMode.alphabetical, tr('alphabetical', lang), Icons.sort_by_alpha),
              _sortItem(_SortMode.ratingHigh, tr('rating_high', lang), Icons.star),
              _sortItem(_SortMode.ratingLow, tr('rating_low', lang), Icons.star_outline),
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
                hintText: tr('filter_by_name', lang),
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
              activeGenres: _activeGenres,
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
                    color: _sortMode == mode ? const Color(0xFF02A9FF) : null,
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
  final Set<String> activeGenres;
  const _MediaList({required this.type, this.searchQuery = '', this.sortMode = _SortMode.lastUpdated, this.activeGenres = const {}});

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

  Map<String, String> _animeStatusLabels(String lang) => {
    'CURRENT': tr('watching', lang),
    'COMPLETED': tr('completed', lang),
    'PAUSED': tr('on_hold', lang),
    'DROPPED': tr('dropped', lang),
    'PLANNING': tr('plan_to_watch', lang),
    'REPEATING': tr('rewatching', lang),
  };

  Map<String, String> _mangaStatusLabels(String lang) => {
    'CURRENT': tr('reading', lang),
    'COMPLETED': tr('completed', lang),
    'PAUSED': tr('on_hold', lang),
    'DROPPED': tr('dropped', lang),
    'PLANNING': tr('plan_to_read', lang),
    'REPEATING': tr('rereading', lang),
  };

  late final AuthService _auth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _auth = context.read<AuthService>();
      _auth.addListener(_onAuthChanged);
      _load();
    });
    listRefreshNotifier.addListener(_silentReload);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    listRefreshNotifier.removeListener(_silentReload);
    super.dispose();
  }

  void _onAuthChanged() {
    if (_auth.isLoggedIn && _lists.isEmpty) {
      _load();
    } else if (!_auth.isLoggedIn) {
      setState(() {
        _lists = {};
        _loading = false;
        _error = 'Connect your AniList from the Profile tab';
      });
    }
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = 'Connect your AniList from the Profile tab';
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

    setState(() { _loading = true; _error = null; });
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
      if (widget.type == 'ANIME' && mounted) {
        final settings = context.read<SettingsProvider>();
        NotificationService().scheduleForAnimeList(typed, settings);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _silentReload() {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    final userId = auth.user?['id'];
    if (userId == null) return;

    () async {
      try {
        final raw = widget.type == 'ANIME'
            ? await _service.getUserAnimeList(userId, auth.token!)
            : await _service.getUserMangaList(userId, auth.token!);
        if (!mounted) return;
        final typed = raw.map(
          (k, v) => MapEntry(k, v.cast<Map<String, dynamic>>()),
        );
        setState(() => _lists = typed);
      } catch (_) {}
    }();
  }

  Future<void> _incrementEpisode(Map<String, dynamic> entry) async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    final media = entry['media'] as Map<String, dynamic>? ?? {};
    final mediaId = media['id'] as int?;
    if (mediaId == null) return;

    final progress = (entry['progress'] as num?)?.toInt() ?? 0;
    final total = widget.type == 'ANIME'
        ? media['episodes'] as int?
        : media['chapters'] as int?;
    if (total != null && progress >= total) return;

    final newProgress = progress + 1;
    final status = (entry['status'] as String?) ?? 'CURRENT';
    final score = (entry['score'] as num?)?.toDouble() ?? 0;

    final ok = await _service.saveListEntry(
      mediaId: mediaId,
      status: status,
      progress: newProgress,
      score: score,
      token: auth.token!,
    );
    if (ok) {
      setState(() => entry['progress'] = newProgress);
      _silentReload();
    }
  }

  Future<void> _removeEntry(Map<String, dynamic> entry) async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    final entryId = entry['id'] as int?;
    if (entryId == null) return;

    final status = (entry['status'] as String?) ?? 'CURRENT';
    final ok = await _service.deleteListEntry(
      entryId: entryId,
      token: auth.token!,
    );
    if (ok) {
      setState(() {
        _lists[status]?.removeWhere((e) => e['id'] == entryId);
      });
      _silentReload();
    }
  }

  List<Map<String, dynamic>> _filterEntries(
      List<Map<String, dynamic>> entries) {
    var result = entries.where((e) {
      final media = e['media'] as Map<String, dynamic>? ?? {};
      if (widget.searchQuery.isNotEmpty) {
        final title = (media['title']?['english'] ??
            media['title']?['romaji'] ??
            '') as String;
        if (!title.toLowerCase().contains(widget.searchQuery.toLowerCase())) return false;
      }
      if (widget.activeGenres.isNotEmpty) {
        final genres = (media['genres'] as List<dynamic>? ?? []).cast<String>();
        if (!widget.activeGenres.any((g) => genres.contains(g))) return false;
      }
      return true;
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
            const Icon(Icons.list_alt_outlined, size: 52, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    if (_lists.isEmpty) {
      final isAnime = widget.type == 'ANIME';
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isAnime ? Icons.movie_filter_outlined : Icons.menu_book_outlined,
                size: 64,
                color: cs.onSurface.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 16),
              Text(
                isAnime ? 'Your anime list is empty' : 'Your manga list is empty',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 8),
              Text(
                isAnime
                    ? 'Start tracking anime you\'re watching or plan to watch'
                    : 'Start tracking manga you\'re reading or plan to read',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.35),
                    height: 1.5),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => MainNavigation.navigateToTab(2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.explore_outlined,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        isAnime ? 'Discover Anime' : 'Discover Manga',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final lang = context.read<SettingsProvider>().language;
    final labels =
        widget.type == 'ANIME' ? _animeStatusLabels(lang) : _mangaStatusLabels(lang);

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

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 52,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text(
              widget.searchQuery.isNotEmpty
                  ? 'No results for "${widget.searchQuery}"'
                  : 'No entries match the selected genres',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                  fontSize: 13)),
          ],
        ),
      );
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
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${item.count}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
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
          final mediaId = item.entry!['media']?['id'] as int?;
          final entryId = item.entry!['id'] as int?;
          return _SwipeableRow(
            key: ValueKey(mediaId ?? entryId ?? i),
            entry: item.entry!,
            type: widget.type,
            onAddEpisode: () => _incrementEpisode(item.entry!),
            onRemove: () => _removeEntry(item.entry!),
          );
        },
      ),
    );
  }
}

// ─── Swipeable Row ──────────────────────────────────────────────────────────

class _SwipeableRow extends StatefulWidget {
  final Map<String, dynamic> entry;
  final String type;
  final VoidCallback onAddEpisode;
  final VoidCallback onRemove;
  const _SwipeableRow({
    super.key,
    required this.entry,
    required this.type,
    required this.onAddEpisode,
    required this.onRemove,
  });

  @override
  State<_SwipeableRow> createState() => _SwipeableRowState();
}

class _SwipeableRowState extends State<_SwipeableRow> {

  String? _timeUntilAiring(int airingAt) {
    final remaining = airingAt - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (remaining <= 0) return null; // already aired — hide the row
    final days = remaining ~/ 86400;
    if (days > 0) return '$days day${days == 1 ? '' : 's'}';
    final hours = remaining ~/ 3600;
    return '$hours hour${hours == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final media = widget.entry['media'] as Map<String, dynamic>? ?? {};
    final progress = (widget.entry['progress'] as num?)?.toInt() ?? 0;
    final score = (widget.entry['score'] as num?)?.toDouble() ?? 0;
    final title = settings.resolveTitle(media['title'] as Map<String, dynamic>?);
    final image = media['coverImage']?['large'] as String?;
    final total = widget.type == 'ANIME'
        ? media['episodes'] as int?
        : media['chapters'] as int?;
    final id = media['id'] as int?;
    final nextAiring = media['nextAiringEpisode'] as Map<String, dynamic>?;
    final unitLabel = widget.type == 'ANIME' ? tr('episode', lang) : tr('chapter', lang);

    return Dismissible(
      key: widget.key ?? ValueKey(id),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          widget.onAddEpisode();
          return false; // don't dismiss, just trigger the action
        } else {
          widget.onRemove();
          return false;
        }
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF4CAF50).withValues(alpha: 0.9), const Color(0xFF4CAF50).withValues(alpha: 0.0)],
            stops: const [0.0, 0.8],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.add, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 6),
            Text(
              unitLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFFF44336).withValues(alpha: 0.0), const Color(0xFFF44336).withValues(alpha: 0.9)],
            stops: const [0.2, 1.0],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('remove', lang),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 6),
            SvgPicture.asset('assets/bin.svg', width: 22, height: 22, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
          ],
        ),
      ),
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: InkWell(
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
                            color: Theme.of(context).colorScheme.surfaceContainerHighest),
                        errorWidget: (_, _, _) => Container(
                            width: 80,
                            height: 115,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest),
                      )
                    : Container(
                        width: 80,
                        height: 115,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest),
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
                      '$progress${total != null ? ' / $total' : ''} ${widget.type == 'ANIME' ? tr('episodes', lang) : tr('chapters', lang)}',
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
                    if (nextAiring != null) Builder(builder: (_) {
                      final nextEp = nextAiring['episode'] as int?;
                      final airingAtRaw = nextAiring['airingAt'];
                      if (nextEp == null || airingAtRaw == null) return const SizedBox.shrink();
                      final airingAt = (airingAtRaw as num).toInt();
                      final timeStr = _timeUntilAiring(airingAt);
                      if (timeStr == null) return const SizedBox.shrink();
                      final behindBy = (nextEp - 1) - progress;
                      final color = behindBy >= 1
                          ? const Color(0xFFFFC107)
                          : const Color(0xFF4CAF50);
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.wifi_rounded, size: 13, color: color),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Episode $nextEp airs in $timeStr',
                                style: TextStyle(fontSize: 12, color: color),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
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
