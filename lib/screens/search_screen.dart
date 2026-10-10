import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/settings_provider.dart';
import '../services/anilist_service.dart';
import '../utils/translations.dart' show tr, trf;
import 'detail_screen.dart';

/// SharedPreferences key of the recent searches; cleared on logout.
const recentSearchesPrefsKey = 'recent_searches';

/// AniList genre names (sent to the API as is) and their display keys.
const _genreKeys = {
  'Action': 'search_genre_action',
  'Adventure': 'search_genre_adventure',
  'Comedy': 'search_genre_comedy',
  'Drama': 'search_genre_drama',
  'Ecchi': 'search_genre_ecchi',
  'Fantasy': 'search_genre_fantasy',
  'Horror': 'search_genre_horror',
  'Mahou Shoujo': 'search_genre_mahou_shoujo',
  'Mecha': 'search_genre_mecha',
  'Music': 'search_genre_music',
  'Mystery': 'search_genre_mystery',
  'Psychological': 'search_genre_psychological',
  'Romance': 'search_genre_romance',
  'Sci-Fi': 'search_genre_sci_fi',
  'Slice of Life': 'search_genre_slice_of_life',
  'Sports': 'search_genre_sports',
  'Supernatural': 'search_genre_supernatural',
  'Thriller': 'search_genre_thriller',
};

/// Translated name of an AniList [genre]; unknown genres are shown as is.
String _genreLabel(String genre, String lang) {
  final key = _genreKeys[genre];
  return key == null ? genre : tr(key, lang);
}

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
  bool _hasError = false;
  bool _searched = false;
  bool _focused = false;

  List<String> _recentSearches = [];
  static const _prefsKey = recentSearchesPrefsKey;

  String _contentType = 'ANIME';
  Set<String> _selectedGenres = {};
  String _sort = 'POPULARITY_DESC';

  final Map<String, List<dynamic>> _cache = {};

  String get _cacheKey =>
      '${_controller.text.trim()}|$_contentType|${_selectedGenres.toList()..sort()}|$_sort';

  /// AniList sort values and the keys of their labels.
  static const _sortLabelKeys = {
    'POPULARITY_DESC': 'popularity',
    'SCORE_DESC': 'search_sort_score',
    'TRENDING_DESC': 'trending_sort',
    'FAVOURITES_DESC': 'search_sort_favorites',
    'TITLE_ROMAJI': 'search_sort_title',
    'START_DATE_DESC': 'search_sort_release_date',
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
        _loading = false;
        _hasError = false;
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
        _loading = false;
        _hasError = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _hasError = false;
    });
    final genres = _selectedGenres.isEmpty ? null : _selectedGenres.toList();
    try {
      final results = _contentType == 'ANIME'
          ? await _service.searchAnime(query, genres: genres, sort: _sort)
          : await _service.searchManga(query, genres: genres, sort: _sort);
      if (!mounted) return;
      // The service returns [] on HTTP errors; don't remember that for the
      // whole session.
      if (results.isNotEmpty) _cache[key] = results;
      _saveSearch(query);
      // A newer query/filter replaced this one while it was in flight.
      if (key != _cacheKey) return;
      setState(() {
        _results = results;
        _loading = false;
        _searched = true;
      });
    } on Exception catch (e) {
      debugPrint('[SearchScreen] Search for "$query" failed: $e');
      if (!mounted || key != _cacheKey) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
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
    final lang = context.watch<SettingsProvider>().language;
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
              hintText: tr('search_hint', lang),
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
                          _loading = false;
                          _hasError = false;
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
                  _loading = false;
                  _hasError = false;
                });
              },
              child: Text(tr('cancel', lang)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'ANIME', child: Text(tr('nav_anime', lang))),
                    PopupMenuItem(value: 'MANGA', child: Text(tr('nav_manga', lang))),
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
                          tr(_contentType == 'ANIME' ? 'nav_anime' : 'nav_manga', lang),
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
                  tooltip: tr('filters', lang),
                ),
                // Sort button
                PopupMenuButton<String>(
                  onSelected: _onSortChanged,
                  tooltip: tr('search_sort', lang),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  itemBuilder: (_) => _sortLabelKeys.entries.map((e) {
                    return PopupMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          Expanded(child: Text(tr(e.value, lang))),
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
                        tr(_sortLabelKeys[_sort] ?? 'search_sort', lang),
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
                : _hasError
                    ? _buildError()
                    : !_searched
                        ? _buildEmptyState(lang)
                        : _results.isEmpty
                            ? Center(child: Text(tr('no_results', lang)))
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

  Widget _buildError() {
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
            onPressed: () => _search(_controller.text.trim()),
            icon: const Icon(Icons.refresh),
            label: Text(tr('retry', lang)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String lang) {
    if (_recentSearches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(tr('search_for', lang),
                style: const TextStyle(color: Colors.grey)),
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
            Text(tr('search_recent', lang),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.55),
                    letterSpacing: 0.3)),
            const Spacer(),
            GestureDetector(
              onTap: _clearRecentSearches,
              child: Text(tr('search_clear_all', lang),
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
    final lang = context.select<SettingsProvider, String>((s) => s.language);
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
        ? trf('search_eps', lang, {'n': episodes})
        : chapters != null
            ? trf('search_ch', lang, {'n': chapters})
            : null;
    final formatLabel = format?.replaceAll('_', ' ');
    final metaParts = [
      ?formatLabel,
      ?episodeLabel,
      if (score != null) '★ ${(score / 10).toStringAsFixed(1)}',
    ];

    return GestureDetector(
      onTap: id == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DetailScreen(animeId: id)),
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
                                _genreLabel(g, lang),
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
    final lang = context.watch<SettingsProvider>().language;
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
                  child: Text(tr('search_reset', lang),
                      style: const TextStyle(color: Colors.grey)),
                ),
                Expanded(
                  child: Center(
                    child: Text(tr('filters', lang),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                Text(
                  tr('genre', lang).toUpperCase(),
                  style: const TextStyle(
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
                  children: _genreKeys.keys.map((g) {
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
                              _genreLabel(g, lang),
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
