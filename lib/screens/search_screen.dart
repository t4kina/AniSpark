import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/settings_provider.dart';
import '../services/anilist_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_text.dart';
import '../utils/translations.dart' show tr, trf;
import '../widgets/app_sheet.dart';
import '../widgets/genre_filter_sheet.dart';
import '../widgets/media_preview.dart';
import '../widgets/motion/cover_hero.dart';
import '../widgets/motion/fade_switcher.dart';
import '../widgets/motion/pressable.dart';
import '../widgets/motion/rounded_hero.dart';
import '../widgets/motion/staggered_entrance.dart';
import '../widgets/option_sheet.dart';
import '../widgets/skeletons.dart';
import '../widgets/state_message.dart';
import 'detail_screen.dart';
import '../widgets/load_error_view.dart';
import '../widgets/app_image.dart';

/// SharedPreferences key of the recent searches; cleared on logout.
const recentSearchesPrefsKey = 'recent_searches';

/// Selected genres in the filters sheet, as search has always shown them.

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.service});

  /// Talks to AniList; tests pass one with a mock client.
  final AniListService? service;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  /// The tap area of a recent search's remove cross.
  static const _removeTapSize = 36.0;

  late final _service = widget.service ?? AniListService();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  List<dynamic> _results = [];
  // Bumped for every new set of results: the old list fades out while the
  // new one fades in, and their covers need different hero tags.
  int _resultsVersion = 0;
  bool _loading = false;
  bool _hasError = false;
  bool _searched = false;
  bool _focused = false;

  List<String> _recentSearches = [];
  static const _prefsKey = recentSearchesPrefsKey;

  /// Anime and manga together, AniList's answer when no type is asked for.
  static const _allTypes = 'ALL';

  String _contentType = _allTypes;
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
        _resultsVersion++;
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
      final results = await _service.searchMedia(
        query,
        type: _contentType == _allTypes ? null : _contentType,
        genres: genres,
        sort: _sort,
      );
      if (!mounted) return;
      // The service returns [] on HTTP errors; don't remember that for the
      // whole session.
      if (results.isNotEmpty) _cache[key] = results;
      _saveSearch(query);
      // A newer query/filter replaced this one while it was in flight.
      if (key != _cacheKey) return;
      setState(() {
        _results = results;
        _resultsVersion++;
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

  static String _typeLabel(String type, String lang) => switch (type) {
        'ANIME' => tr('nav_anime', lang),
        'MANGA' => tr('nav_manga', lang),
        _ => tr('search_all_types', lang),
      };

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
    showAppSheet<void>(
      context: context,
      builder: (_) => GenreFilterSheet(
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
          // The field keeps the page's margin at the right; Cancel, when
          // it shows, brings its own.
          padding: EdgeInsets.only(left: 16, right: _focused || _controller.text.isNotEmpty ? 4 : 16),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            decoration: InputDecoration(
              hintText: tr('search_hint', lang),
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search, size: 20, color: context.colors.textSecondary),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
                _pickerButton(
                  name: tr('search_content_type', lang),
                  value: _typeLabel(_contentType, lang),
                  onTap: () => showOptionSheet<String>(
                    context: context,
                    title: tr('search_content_type', lang),
                    options: const [_allTypes, 'ANIME', 'MANGA'],
                    labelOf: (type) => _typeLabel(type, lang),
                    current: _contentType,
                    onSelected: _onContentTypeChanged,
                  ),
                  child: _controlPill(_typeLabel(_contentType, lang)),
                ),
                const Spacer(),
                // Filter button
                IconButton(
                  // Counts the genres the results are filtered by.
                  icon: Badge(
                    isLabelVisible: hasFilters,
                    label: Text('${_selectedGenres.length}'),
                    backgroundColor: accentColor,
                    textColor: Theme.of(context).colorScheme.onPrimary,
                    child: Icon(Icons.tune, color: hasFilters ? accentColor : context.colors.textSecondary),
                  ),
                  onPressed: _showFilters,
                  tooltip: tr('filters', lang),
                ),
                // Sort button
                _pickerButton(
                  name: tr('search_sort', lang),
                  value: tr(_sortLabelKeys[_sort] ?? 'search_sort', lang),
                  onTap: () => showOptionSheet<String>(
                    context: context,
                    title: tr('search_sort', lang),
                    options: _sortLabelKeys.keys.toList(),
                    labelOf: (v) => tr(_sortLabelKeys[v] ?? 'search_sort', lang),
                    current: _sort,
                    onSelected: _onSortChanged,
                  ),
                  child: _controlPill(tr(_sortLabelKeys[_sort] ?? 'search_sort', lang)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Results
          Expanded(child: FadeSwitcher(child: _buildResults(lang))),
        ],
      ),
    );
  }

  /// A control that opens an option sheet, read as a button named [name]
  /// whose value is the current choice.
  static Widget _pickerButton({
    required String name,
    required String value,
    required VoidCallback onTap,
    required Widget child,
  }) =>
      Semantics(
        button: true,
        label: name,
        value: value,
        child: Pressable(onTap: onTap, child: ExcludeSemantics(child: child)),
      );

  /// What a picker of the control row shows: its current choice in a pill,
  /// the same for the content type and the sort.
  Widget _controlPill(String label) => Container(
        padding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.pillAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppText.footnote.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down, size: 16, color: context.colors.textSecondary),
          ],
        ),
      );

  /// The area under the controls; each state has its own key so changing
  /// state (or getting new results) cross-fades.
  Widget _buildResults(String lang) {
    if (_loading) {
      return const _ResultsSkeleton(key: ValueKey('loading'));
    }
    if (_hasError) {
      return LoadErrorView(key: const ValueKey('error'), onRetry: () => _search(_controller.text.trim()));
    }
    if (!_searched) return KeyedSubtree(key: const ValueKey('start'), child: _buildEmptyState(lang));
    if (_results.isEmpty) {
      return StateMessage(
        key: const ValueKey('no-results'),
        icon: Icons.search_off_rounded,
        message: tr('no_results', lang),
      );
    }
    final heroScope = 'search-$_resultsVersion';
    final results = _results;
    return EntranceGate(
      key: ValueKey(heroScope),
      trigger: results,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: results.length,
        itemBuilder: (_, i) => StaggeredEntrance(
          index: i,
          child: _ResultCard(data: results[i], heroScope: heroScope),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String lang) {
    if (_recentSearches.isEmpty) {
      return StateMessage(icon: Icons.search, message: tr('search_for', lang));
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
            Pressable.dim(
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
            return Pressable(
              onTap: () {
                _controller.text = q;
                _controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: q.length));
                _search(q);
              },
              child: Container(
                padding: const EdgeInsets.only(left: 12),
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
                    // A whole finger's room to remove it, not just the cross.
                    Semantics(
                      button: true,
                      label: tr('search_remove_recent', lang),
                      child: Pressable.dim(
                        onTap: () => _removeRecentSearch(q),
                        child: SizedBox.square(
                          dimension: _removeTapSize,
                          child: Icon(Icons.close_rounded, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
                        ),
                      ),
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

/// Placeholder shaped like the result cards.
class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8),
        itemCount: 6,
        itemBuilder: (_, _) => const Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: SkeletonBox(height: 140, radius: 10),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final dynamic data;

  /// The results list's scope for the cover's hero tag.
  final String heroScope;

  const _ResultCard({required this.data, required this.heroScope});

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
    final heroTag = id == null ? null : coverHeroTag(heroScope, id);


    return Pressable(
      // A full-width card only needs a hint of a press.
      pressedScale: 0.98,
      onLongPress: id == null ? null : () => showMediaPreview(context, media: data as Map<String, dynamic>),
      onTap: id == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetailScreen(animeId: id, heroTag: heroTag, initialCoverUrl: cover),
                ),
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
            if (banner != null) AppImage(url: banner, cacheWidth: 600, fill: false),
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
                  SizedBox(
                    width: 78,
                    height: 116,
                    child: RoundedHero(
                      tag: heroTag,
                      borderRadius: const BorderRadius.all(Radius.circular(6)),
                      child: AppImage(url: cover, cacheWidth: 160),
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
                                genreLabel(g, lang),
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
