import 'dart:math' show max;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/api_cache.dart';
import '../services/discover_api.dart';
import '../utils/anime_season.dart';
import '../utils/translations.dart' show tr, trf;
import '../widgets/skeletons.dart';
import 'detail_screen.dart';

/// Browses the anime of any season, sorted and filtered by format, loading
/// more as the grid scrolls.
class SeasonScreen extends StatefulWidget {
  const SeasonScreen({super.key, this.initial, this.api});

  /// The season shown first; defaults to the one airing now.
  final SeasonYear? initial;

  /// Replaces the AniList API, for tests.
  final DiscoverApi? api;

  @override
  State<SeasonScreen> createState() => _SeasonScreenState();
}

const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 160,
  crossAxisSpacing: 10,
  mainAxisSpacing: 12,
  childAspectRatio: 0.5,
);

/// AniList formats offered as filters.
const _formatOptions = ['TV', 'TV_SHORT', 'MOVIE', 'OVA', 'ONA', 'SPECIAL', 'MUSIC'];

// TV, OVA and ONA read the same in every language, so they fall through
// (like the detail screen).
String _formatLabel(String format, String lang) => switch (format) {
      'MOVIE' => tr('movie', lang),
      'SPECIAL' => tr('special', lang),
      'MUSIC' => tr('detail_format_music', lang),
      'TV_SHORT' => tr('detail_format_tv_short', lang),
      _ => format,
    };

String _seasonKey(AnimeSeason season) => switch (season) {
      AnimeSeason.winter => 'detail_season_winter',
      AnimeSeason.spring => 'detail_season_spring',
      AnimeSeason.summer => 'detail_season_summer',
      AnimeSeason.fall => 'detail_season_fall',
    };

class _SeasonScreenState extends State<SeasonScreen> {
  static const _maxAge = Duration(hours: 1);
  static const _firstYear = 1940;
  // Starts loading the next page this close to the end of the grid.
  static const _loadMoreExtent = 600.0;

  static const _titleSort = 'TITLE';

  /// Sort options (AniList `MediaSort`s, plus [_titleSort]) and label keys.
  static const _sortLabelKeys = {
    'POPULARITY_DESC': 'popularity',
    'SCORE_DESC': 'search_sort_score',
    'TRENDING_DESC': 'trending_sort',
    _titleSort: 'search_sort_title',
  };

  late final DiscoverApi _api = widget.api ?? DiscoverApi();
  final _scroll = ScrollController();

  late SeasonYear _season = _clamp(widget.initial ?? SeasonYear.of(DateTime.now()));
  String _sort = 'POPULARITY_DESC';
  Set<String> _formats = const {};

  Map<int, SeasonPage> _pages = const {};
  bool _loadingFirst = true;
  bool _loadingMore = false;
  bool _hasError = false;
  bool _moreError = false;
  // Bumped when the selection changes so stale responses are ignored.
  int _generation = 0;

  static const _firstSeason = SeasonYear(AnimeSeason.winter, _firstYear);
  SeasonYear get _lastSeason => SeasonYear(AnimeSeason.fall, DateTime.now().year + 1);

  /// Keeps [season] within the browsable range (the year picker requires it).
  SeasonYear _clamp(SeasonYear season) {
    if (season.isBefore(_firstSeason)) return _firstSeason;
    if (season.isAfter(_lastSeason)) return _lastSeason;
    return season;
  }

  int get _lastPage => _pages.keys.fold(0, max);
  // An empty page ends the list even if AniList says more follow.
  bool get _hasNextPage {
    final page = _pages[_lastPage];
    return page != null && page.hasNextPage && page.media.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadPage(1);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The AniList sort for [_sort]; titles sort in the language they're shown.
  String _apiSort() {
    if (_sort != _titleSort) return _sort;
    return switch (context.read<SettingsProvider>().titleLanguage) {
      'Romaji' => 'TITLE_ROMAJI',
      'Native' => 'TITLE_NATIVE',
      // Entries without an English title sort by romaji, as they're shown.
      _ => 'TITLE_ENGLISH',
    };
  }

  /// e.g. `season:FALL-2026:POPULARITY_DESC:TV+OVA:p1`; public data.
  String _cacheKey(String sort, int page) {
    final formats = _formats.isEmpty ? 'ALL' : (_formats.toList()..sort()).join('+');
    return 'season:${_season.key}:$sort:$formats:p$page';
  }

  /// Loads [page] of the current selection, from the cache first.
  Future<void> _loadPage(int page, {bool force = false}) async {
    final generation = _generation;
    final season = _season;
    final formats = _formats;
    final sort = _apiSort();
    final key = _cacheKey(sort, page);
    final cache = context.read<ApiCache>();
    if (page > 1) {
      setState(() {
        _loadingMore = true;
        _moreError = false;
      });
    } else if (_hasError) {
      setState(() {
        _hasError = false;
        _loadingFirst = _pages.isEmpty;
      });
    }
    bool isCurrent() => mounted && generation == _generation;

    var loaded = false;
    try {
      await cache.load<SeasonPage>(
        key: key,
        fetch: () => _api.seasonMedia(
          season: season.season.apiName,
          year: season.year,
          sort: sort,
          formats: formats,
          page: page,
        ),
        decode: SeasonPage.fromJson,
        onData: (result, {required isFresh}) {
          if (!isCurrent()) return;
          setState(() {
            _pages = {..._pages, page: result};
            if (page == 1) _loadingFirst = false;
          });
        },
        maxAge: _maxAge,
        force: force,
      );
      loaded = true;
    } on Exception catch (e) {
      debugPrint('[SeasonScreen] Loading $key failed: $e');
      if (isCurrent()) {
        final hasData = _pages.isNotEmpty;
        setState(() {
          if (page == 1) {
            _hasError = !hasData;
          } else {
            _moreError = true;
          }
        });
        if (page == 1 && force && hasData) _showLoadError();
      }
    }
    if (!isCurrent()) return;
    setState(() {
      if (page == 1) {
        _loadingFirst = false;
      } else {
        _loadingMore = false;
      }
    });
    // Keep loading if this page didn't fill the screen.
    if (loaded) WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter > _loadMoreExtent) return;
    if (_loadingFirst || _loadingMore || _hasError || _moreError || !_hasNextPage) return;
    _loadPage(_lastPage + 1);
  }

  void _showLoadError() {
    final lang = context.read<SettingsProvider>().language;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('load_error', lang))));
  }

  /// Switches to a new season, sort or format filter and loads its first page.
  void _select({SeasonYear? season, String? sort, Set<String>? formats}) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _season = season ?? _season;
      _sort = sort ?? _sort;
      _formats = formats ?? _formats;
      _generation++;
      _pages = const {};
      _loadingFirst = true;
      _loadingMore = false;
      _hasError = false;
      _moreError = false;
    });
    _loadPage(1);
  }

  /// Pull to refresh: reloads the first page and drops the rest, which then
  /// load again on scroll.
  Future<void> _refresh() {
    setState(() {
      _generation++;
      _pages = {1: ?_pages[1]};
      _loadingMore = false;
      _moreError = false;
    });
    return _loadPage(1, force: true);
  }

  void _toggleFormat(String format) => _select(
        formats: _formats.contains(format)
            ? _formats.difference({format})
            : {..._formats, format},
      );

  Future<void> _pickYear(String lang) async {
    final year = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('season_pick_year', lang)),
        content: SizedBox(
          width: 300,
          height: 320,
          child: YearPicker(
            firstDate: DateTime(_firstYear),
            lastDate: DateTime(_lastSeason.year),
            selectedDate: DateTime(_season.year),
            onChanged: (date) => Navigator.pop(ctx, date.year),
          ),
        ),
      ),
    );
    if (!mounted || year == null || year == _season.year) return;
    _select(season: SeasonYear(_season.season, year));
  }

  String _seasonLabel(String lang) => trf('detail_season_year', lang, {
        'season': tr(_seasonKey(_season.season), lang),
        'year': _season.year,
      });

  /// Items of every loaded page, without repeats when the order shifted
  /// between pages.
  List<Map<String, dynamic>> get _items {
    final seen = <Object?>{};
    return [
      for (final page in _pages.keys.toList()..sort())
        for (final media in _pages[page]?.media ?? const <Map<String, dynamic>>[])
          if (seen.add(media['id'])) media,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final canGoBack = _season.isAfter(_firstSeason);
    final canGoForward = _season.isBefore(_lastSeason);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _seasonLabel(lang),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: tr('season_previous', lang),
            onPressed: canGoBack ? () => _select(season: _season.previous) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: tr('season_next', lang),
            onPressed: canGoForward ? () => _select(season: _season.next) : null,
          ),
          _buildSortMenu(lang),
        ],
      ),
      body: Column(
        children: [
          _buildSeasonRow(lang),
          _buildFormatRow(lang),
          const Divider(height: 1),
          Expanded(child: _buildContent(lang)),
        ],
      ),
    );
  }

  Widget _buildSortMenu(String lang) => PopupMenuButton<String>(
        icon: const Icon(Icons.sort),
        tooltip: tr('search_sort', lang),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (sort) {
          if (sort != _sort) _select(sort: sort);
        },
        itemBuilder: (ctx) => [
          for (final MapEntry(key: sort, value: labelKey) in _sortLabelKeys.entries)
            PopupMenuItem(
              value: sort,
              child: Row(
                children: [
                  Expanded(child: Text(tr(labelKey, lang))),
                  if (sort == _sort)
                    Icon(Icons.check, size: 16, color: Theme.of(ctx).colorScheme.primary),
                ],
              ),
            ),
        ],
      );

  Widget _buildSeasonRow(String lang) => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            ActionChip(
              avatar: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text('${_season.year}'),
              tooltip: tr('season_pick_year', lang),
              onPressed: () => _pickYear(lang),
            ),
            const SizedBox(width: 12),
            for (final season in AnimeSeason.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(tr(_seasonKey(season), lang)),
                  selected: _season.season == season,
                  onSelected: (_) {
                    if (season != _season.season) {
                      _select(season: SeasonYear(season, _season.year));
                    }
                  },
                ),
              ),
          ],
        ),
      );

  Widget _buildFormatRow(String lang) => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(tr('season_format_all', lang)),
                selected: _formats.isEmpty,
                onSelected: (_) {
                  if (_formats.isNotEmpty) _select(formats: const {});
                },
              ),
            ),
            for (final format in _formatOptions)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(_formatLabel(format, lang)),
                  selected: _formats.contains(format),
                  onSelected: (_) => _toggleFormat(format),
                ),
              ),
          ],
        ),
      );

  Widget _buildContent(String lang) {
    if (_loadingFirst && _pages.isEmpty) return const _GridSkeleton();
    if (_hasError) return _buildError(lang);
    final items = _items;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(tr('no_results', lang), style: const TextStyle(color: Colors.grey)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid.builder(
                gridDelegate: _gridDelegate,
                itemCount: items.length,
                itemBuilder: (_, i) => _SeasonTile(media: items[i], lang: lang),
              ),
            ),
          SliverToBoxAdapter(child: _buildFooter(lang)),
        ],
      ),
    );
  }

  Widget _buildFooter(String lang) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_moreError) return const SizedBox(height: 16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        children: [
          Text(tr('load_error', lang), style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _loadPage(_lastPage + 1),
            icon: const Icon(Icons.refresh),
            label: Text(tr('retry', lang)),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String lang) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(tr('load_error', lang), style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _loadPage(1),
              icon: const Icon(Icons.refresh),
              label: Text(tr('retry', lang)),
            ),
          ],
        ),
      );
}

/// Grid cover with score, title, format and episode count.
class _SeasonTile extends StatelessWidget {
  const _SeasonTile({required this.media, required this.lang});

  final Map<String, dynamic> media;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final id = media['id'] as int?;
    final cover = (media['coverImage'] as Map?)?['large'] as String?;
    final title = context
        .read<SettingsProvider>()
        .resolveTitle(media['title'] as Map<String, dynamic>?);
    final score = (media['averageScore'] as num?)?.toInt();
    final format = media['format'] as String?;
    final episodes = (media['episodes'] as num?)?.toInt();
    final details = [
      if (format != null) _formatLabel(format, lang),
      if (episodes != null) trf('search_eps', lang, {'n': episodes}),
    ].join(' · ');
    final placeholder =
        Container(color: Theme.of(context).colorScheme.surfaceContainerHighest);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: id == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DetailScreen(animeId: id)),
              ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover == null)
                    placeholder
                  else
                    CachedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      memCacheWidth: 240,
                      placeholder: (_, _) => placeholder,
                      errorWidget: (_, _, _) => placeholder,
                    ),
                  if (score != null) _ScoreOverlay(score: score),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (details.isNotEmpty)
            Text(
              details,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}

/// "★ 8.5" over the bottom of a cover; [score] is AniList's 0–100.
class _ScoreOverlay extends StatelessWidget {
  const _ScoreOverlay({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) => Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
            ),
          ),
          child: Text(
            '★ ${(score / 10).toStringAsFixed(1)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

/// Placeholder shaped like the cover grid.
class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) => Skeleton(
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: _gridDelegate,
          itemCount: 12,
          itemBuilder: (_, _) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SkeletonBox(height: double.infinity, radius: 8)),
              SizedBox(height: 5),
              SkeletonBox(height: 12),
              SizedBox(height: 4),
              SkeletonBox(width: 60, height: 10),
            ],
          ),
        ),
      );
}
