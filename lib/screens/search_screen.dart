import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/anilist_service.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _service = AniListService();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  List<dynamic> _results = [];
  bool _loading = false;
  bool _searched = false;
  bool _focused = false;

  List<String> _recentSearches = [];
  static const _prefsKey = 'recent_searches';

  String _contentType = 'ANIME';
  Set<String> _selectedGenres = {};
  String _sort = 'POPULARITY_DESC';

  final Map<String, List<dynamic>> _cache = {};

  String get _cacheKey =>
      '${_controller.text.trim()}|$_contentType|${_selectedGenres.toList()..sort()}|$_sort';

  static const _sortLabels = {
    'POPULARITY_DESC': 'Popularity',
    'SCORE_DESC': 'Score',
    'TRENDING_DESC': 'Trending',
    'FAVOURITES_DESC': 'Favorites',
    'TITLE_ROMAJI': 'Title',
    'START_DATE_DESC': 'Release Date',
  };

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() => _focused = _focusNode.hasFocus));
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    if (mounted) setState(() => _recentSearches = raw);
  }

  Future<void> _saveSearch(String query) async {
    final updated = [query, ..._recentSearches.where((s) => s != query)]
        .take(8)
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, updated);
    if (mounted) setState(() => _recentSearches = updated);
  }

  Future<void> _removeRecentSearch(String query) async {
    final updated = _recentSearches.where((s) => s != query).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, updated);
    setState(() => _recentSearches = updated);
  }

  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    setState(() => _recentSearches = []);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) return;
    final key = _cacheKey;
    if (_cache.containsKey(key)) {
      setState(() {
        _results = _cache[key]!;
        _searched = true;
      });
      return;
    }
    setState(() => _loading = true);
    final genres = _selectedGenres.isEmpty ? null : _selectedGenres.toList();
    final results = _contentType == 'ANIME'
        ? await _service.searchAnime(query, genres: genres, sort: _sort)
        : await _service.searchManga(query, genres: genres, sort: _sort);
    if (!mounted) return;
    _cache[key] = results;
    _saveSearch(query);
    setState(() {
      _results = results;
      _loading = false;
      _searched = true;
    });
  }

  void _onContentTypeChanged(String type) {
    if (type == _contentType) return;
    setState(() {
      _contentType = type;
      _results = [];
      _searched = false;
    });
    final q = _controller.text.trim();
    if (q.isNotEmpty) _search(q);
  }

  void _onSortChanged(String sort) {
    if (sort == _sort) return;
    setState(() {
      _sort = sort;
      _cache.clear();
      _results = [];
    });
    final q = _controller.text.trim();
    if (q.isNotEmpty) _search(q);
  }

  void _showFilters() {
    final draft = Set<String>.from(_selectedGenres);
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FilterSheet(
        selected: draft,
        onApply: (genres) {
          if (genres == _selectedGenres) return;
          setState(() {
            _selectedGenres = genres;
            _cache.clear();
            _results = [];
          });
          final q = _controller.text.trim();
          if (q.isNotEmpty) _search(q);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFilters = _selectedGenres.isNotEmpty;
    final accentColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() {
                          _results = [];
                          _searched = false;
                        });
                      },
                    )
                  : null,
            ),
            onChanged: _onQueryChanged,
            onSubmitted: _search,
          ),
        ),
        actions: [
          if (_focused || _controller.text.isNotEmpty)
            TextButton(
              onPressed: () {
                _focusNode.unfocus();
                _controller.clear();
                setState(() {
                  _results = [];
                  _searched = false;
                  _focused = false;
                });
              },
              child: const Text('Cancel'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Control row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                // Content type pill
                PopupMenuButton<String>(
                  onSelected: _onContentTypeChanged,
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'ANIME', child: Text('Anime')),
                    PopupMenuItem(value: 'MANGA', child: Text('Manga')),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _contentType == 'ANIME' ? 'Anime' : 'Manga',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, size: 16),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // Filter button
                IconButton(
                  icon: Icon(
                    Icons.tune,
                    color: hasFilters ? accentColor : Colors.grey,
                  ),
                  onPressed: _showFilters,
                  tooltip: 'Filters',
                ),
                // Sort button
                PopupMenuButton<String>(
                  onSelected: _onSortChanged,
                  tooltip: 'Sort',
                  itemBuilder: (_) => _sortLabels.entries.map((e) {
                    return PopupMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          Expanded(child: Text(e.value)),
                          if (e.key == _sort)
                            Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    );
                  }).toList(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _sortLabels[_sort] ?? 'Sort',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const Icon(Icons.keyboard_arrow_down, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Results
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_searched
                    ? _buildEmptyState()
                    : _results.isEmpty
                        ? const Center(child: Text('No results found'))
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 8, bottom: 16),
                            itemCount: _results.length,
                            itemBuilder: (_, i) => _ResultCard(data: _results[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_recentSearches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.search, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('Search for anime or manga',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Text('Recent',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.55),
                    letterSpacing: 0.3)),
            const Spacer(),
            GestureDetector(
              onTap: _clearRecentSearches,
              child: Text('Clear all',
                  style: TextStyle(fontSize: 12, color: cs.primary)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _recentSearches.map((q) {
            return GestureDetector(
              onTap: () {
                _controller.text = q;
                _controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: q.length));
                _search(q);
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_rounded, size: 14,
                        color: cs.onSurface.withValues(alpha: 0.45)),
                    const SizedBox(width: 6),
                    Text(q,
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurface.withValues(alpha: 0.85))),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _removeRecentSearch(q),
                      child: Icon(Icons.close_rounded, size: 14,
                          color: cs.onSurface.withValues(alpha: 0.35)),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Result card ──────────────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  final dynamic data;
  const _ResultCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final id = data['id'] as int?;
    final title = data['title']?['english'] ?? data['title']?['romaji'] ?? '';
    final cover = data['coverImage']?['large'] as String?;
    final banner = data['bannerImage'] as String?;
    final score = data['averageScore'] as int?;
    final episodes = data['episodes'] as int?;
    final chapters = data['chapters'] as int?;
    final format = data['format'] as String?;
    final genres = (data['genres'] as List<dynamic>?)?.cast<String>() ?? [];
    final description = (data['description'] as String? ?? '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();

    final episodeLabel = episodes != null
        ? '$episodes eps'
        : chapters != null
            ? '$chapters ch'
            : null;
    final formatLabel = format?.replaceAll('_', ' ');
    final metaParts = [
      ?formatLabel,
      ?episodeLabel,
      if (score != null) '★ ${(score / 10).toStringAsFixed(1)}',
    ];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetailScreen(animeId: id ?? 0)),
      ),
      child: Container(
        height: 140,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Banner background
            if (banner != null)
              CachedNetworkImage(
                imageUrl: banner,
                fit: BoxFit.cover,
                memCacheWidth: 600,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            // Dark overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 78,
                      height: 116,
                      child: cover != null
                          ? CachedNetworkImage(
                              imageUrl: cover,
                              fit: BoxFit.cover,
                              memCacheWidth: 160,
                              errorWidget: (_, _, _) => Container(
                                color: Colors.grey[800],
                              ),
                            )
                          : Container(color: Colors.grey[800]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (metaParts.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            metaParts.join(' · '),
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Expanded(
                            child: Text(
                              description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                        if (genres.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 0,
                            children: genres.take(3).map((g) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                g,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                            )).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter sheet ─────────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final Set<String> selected;
  final void Function(Set<String>) onApply;

  const _FilterSheet({required this.selected, required this.onApply});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _draft;

  static const _genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy',
    'Horror', 'Mahou Shoujo', 'Mecha', 'Music', 'Mystery', 'Psychological',
    'Romance', 'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural', 'Thriller',
  ];

  @override
  void initState() {
    super.initState();
    _draft = Set<String>.from(widget.selected);
  }

  void _close() {
    Navigator.pop(context);
    widget.onApply(_draft);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _draft.clear()),
                  child: const Text('Reset', style: TextStyle(color: Colors.grey)),
                ),
                const Expanded(
                  child: Center(
                    child: Text('Filters',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _close,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const Text(
                  'GENRE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _genres.map((g) {
                    final selected = _draft.contains(g);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (selected) {
                          _draft.remove(g);
                        } else {
                          _draft.add(g);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF2ECC71).withValues(alpha: 0.2)
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF2ECC71)
                                : Colors.transparent,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (selected) ...[
                              const Icon(Icons.check, size: 14, color: Color(0xFF2ECC71)),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              g,
                              style: TextStyle(
                                fontSize: 13,
                                color: selected ? const Color(0xFF2ECC71) : null,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
