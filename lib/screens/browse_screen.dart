import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/api_cache.dart';
import '../services/browse_api.dart';
import '../theme/app_motion.dart';
import '../utils/translations.dart' show tr, trf;
import '../widgets/anime_card.dart';
import '../widgets/genre_filter_sheet.dart';
import '../widgets/motion/fade_switcher.dart';
import '../widgets/motion/pressable.dart';
import '../widgets/motion/staggered_entrance.dart';
import '../widgets/people/paged_items.dart';
import '../widgets/skeletons.dart';

/// A Discover row's "See all": the row's [query] as a grid that loads more
/// as it scrolls, under a bar of sort, rating, genre and format filters.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    required this.title,
    required this.query,
    this.initialItems = const [],
    this.api,
  });

  final String title;

  /// The row's query, without user filters.
  final BrowseQuery query;

  /// What the row already shows, on screen until the first page arrives.
  final List<dynamic> initialItems;

  /// Replaces the AniList API, for tests.
  final BrowseApi? api;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 3,
  crossAxisSpacing: 10,
  mainAxisSpacing: 10,
  childAspectRatio: 0.53,
);

const _gridPadding = EdgeInsets.all(12);

/// Height of the filter bar under the app bar (pills plus their tap margin).
const _filterBarHeight = 52.0;

/// Sort options (AniList `MediaSort`s) and the keys of their labels.
const _sortLabelKeys = {
  'TRENDING_DESC': 'trending_sort',
  'POPULARITY_DESC': 'popularity',
  'SCORE_DESC': 'search_sort_score',
  BrowseQuery.newestSort: 'newest',
};

/// Minimum ratings offered (AniList's 0–100 average score); 0 is any.
const _minScoreOptions = [0, 60, 70, 80];

const _animeFormats = ['TV', 'MOVIE', 'OVA', 'ONA', 'SPECIAL', 'TV_SHORT'];
const _mangaFormats = ['MANGA', 'ONE_SHOT'];

// TV, OVA and ONA read the same in every language (like the detail page).
String _formatLabel(String format, String lang) => switch (format) {
      'MOVIE' => tr('movie', lang),
      'SPECIAL' => tr('special', lang),
      'TV_SHORT' => tr('detail_format_tv_short', lang),
      'MANGA' => tr('source_manga', lang),
      'ONE_SHOT' => tr('detail_format_one_shot', lang),
      _ => format,
    };

String _minScoreLabel(int score, String lang) =>
    score == 0 ? tr('browse_any', lang) : trf('browse_score_at_least', lang, {'n': score ~/ 10});

/// The first of [values] in [order] and how many others there are, e.g.
/// `Action +2`.
String _summary(Set<String> values, Iterable<String> order, String Function(String) label) {
  final first = order.firstWhere(values.contains, orElse: () => values.first);
  return values.length == 1 ? label(first) : '${label(first)} +${values.length - 1}';
}

class _BrowseScreenState extends State<BrowseScreen> with PagedLoading<BrowseScreen> {
  static const _maxAge = Duration(hours: 1);
  // Starts loading the next page this close to the end of the grid.
  static const _loadMoreExtent = 600.0;

  late final BrowseApi _api = widget.api ?? BrowseApi();
  final _scroll = ScrollController();

  late BrowseQuery _query = widget.query;

  /// What the grid shows: the row's own items (no page loaded yet) until the
  /// first page replaces them.
  late PagedItems<Map<String, dynamic>> _paged =
      PagedItems(items: List.unmodifiable(widget.initialItems.whereType<Map<String, dynamic>>()));
  bool _loadingFirst = true;

  /// The first page failed while only the row's items (or nothing) showed.
  bool _firstFailed = false;

  // Bumped for every first-page load so an older one that answers late is
  // ignored.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(loadMoreIfNearEnd);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<String> get _formatOptions => _query.isManga ? _mangaFormats : _animeFormats;

  /// Loads the first page of [_query] (the row's own query from the cache
  /// first) and shows it in place of what the grid had.
  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    resetPaging();
    final query = _query;
    bool isCurrent() => mounted && generation == _generation;
    void show(BrowsePage page) {
      if (!isCurrent()) return;
      setState(() => _paged = PagedItems.firstPage(page.media, hasNextPage: page.hasNextPage));
    }

    try {
      if (query.isDefault) {
        await context.read<ApiCache>().load<BrowsePage>(
              key: 'browse:${query.id}',
              fetch: () => _api.browse(query),
              decode: BrowsePage.fromJson,
              onData: (page, {required isFresh}) => show(page),
              maxAge: _maxAge,
              // Never let an empty answer replace a good cached page.
              isValid: (page) => page.media.isNotEmpty,
            );
      } else {
        show(await _api.browse(query));
      }
    } on Exception catch (e) {
      debugPrint('[BrowseScreen] Loading ${query.id} ${query.filterKey} failed: $e');
      // A cached first page already on screen stays and pages on.
      if (isCurrent()) setState(() => _firstFailed = _paged.lastPage == 0);
    }
    if (!isCurrent()) return;
    setState(() => _loadingFirst = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => loadMoreIfNearEnd());
  }

  void _retryFirstPage() {
    setState(() {
      _loadingFirst = true;
      _firstFailed = false;
    });
    _loadFirstPage();
  }

  @override
  void loadMoreIfNearEnd() {
    if (!mounted || _loadingFirst || !_paged.canLoadMore) return;
    // A page whose titles were all filtered out leaves nothing to scroll.
    if (_paged.items.isEmpty) return _loadMore();
    if (!_scroll.hasClients) return;
    // While a new grid fades in over the old one both use the controller;
    // the newest is the one that pages.
    if (_scroll.positions.last.extentAfter > _loadMoreExtent) return;
    _loadMore();
  }

  void _loadMore({bool retry = false}) {
    final query = _query;
    loadNextPage<Map<String, dynamic>>(
      read: () => _paged,
      write: (value) => _paged = value,
      fetch: (page) async {
        final result = await _api.browse(query, page: page);
        return (result.media, result.hasNextPage);
      },
      merge: _merge,
      debugLabel: 'BrowseScreen',
      retry: retry,
    );
  }

  /// [shown] followed by the media of [page] it doesn't have yet (the order
  /// can shift between pages).
  static List<Map<String, dynamic>> _merge(List<Map<String, dynamic>> shown, List<Map<String, dynamic>> page) {
    final ids = {for (final media in shown) media['id']};
    return List.unmodifiable([...shown, ...page.where((media) => ids.add(media['id']))]);
  }

  /// Shows [query]'s results from its first page, at the top of the grid.
  void _apply(BrowseQuery query) {
    if (query == _query) return;
    setState(() {
      _query = query;
      _paged = const PagedItems();
      _loadingFirst = true;
      _firstFailed = false;
    });
    // The leaving grid scrolls up as it fades out (and resets the app bar).
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadFirstPage();
  }

  void _clearFilters() => _apply(_query.defaults);

  Future<T?> _showSheet<T>(WidgetBuilder builder) => showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: builder,
      );

  Future<void> _pickSort(String lang) async {
    final sort = await _showSheet<String>((_) => _ChoiceSheet(
          title: tr('sort_by', lang),
          options: [
            for (final MapEntry(key: sort, value: labelKey) in _sortLabelKeys.entries) (sort, tr(labelKey, lang)),
          ],
          selected: _query.sort,
        ));
    if (!mounted || sort == null) return;
    _apply(_query.copyWith(sort: sort));
  }

  Future<void> _pickMinScore(String lang) async {
    final score = await _showSheet<int>((_) => _ChoiceSheet(
          title: tr('browse_rating', lang),
          options: [for (final score in _minScoreOptions) (score, _minScoreLabel(score, lang))],
          selected: _query.minScore,
        ));
    if (!mounted || score == null) return;
    _apply(_query.copyWith(minScore: score));
  }

  /// Picks several values in a sheet; they apply once it closes, however
  /// it's closed.
  Future<void> _pickMany({
    required String title,
    required Set<String> selected,
    required Widget Function(Set<String> selected, ValueChanged<String> toggle) chips,
    required BrowseQuery Function(Set<String> picked) apply,
  }) async {
    var picked = selected;
    await _showSheet<void>((_) => _MultiChoiceSheet(
          title: title,
          initial: selected,
          onChanged: (value) => picked = value,
          chips: chips,
        ));
    if (!mounted) return;
    _apply(apply(picked));
  }

  Future<void> _pickGenres(String lang) => _pickMany(
        title: tr('browse_genres', lang),
        selected: _query.genres,
        chips: (selected, toggle) => GenreChips(selected: selected, onToggle: toggle),
        apply: (genres) => _query.copyWith(genres: genres),
      );

  Future<void> _pickFormats(String lang) => _pickMany(
        title: tr('format', lang),
        selected: _query.formats,
        chips: (selected, toggle) => Wrap(
          spacing: 8,
          children: [
            for (final format in _formatOptions)
              FilterOptionChip(
                key: ValueKey('browse-option-$format'),
                label: _formatLabel(format, lang),
                selected: selected.contains(format),
                onTap: () => toggle(format),
              ),
          ],
        ),
        apply: (formats) => _query.copyWith(formats: formats),
      );

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(_filterBarHeight + 1),
          child: Column(
            children: [
              SizedBox(height: _filterBarHeight, child: _buildFilterBar(lang)),
              const Divider(height: 1),
            ],
          ),
        ),
      ),
      body: FadeSwitcher(child: _buildState(lang)),
    );
  }

  Widget _buildFilterBar(String lang) {
    final query = _query;
    final duration = AppMotion.of(context, AppMotion.short);
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      children: [
        // Clear slides in at the start, where it can't be scrolled away.
        AnimatedSwitcher(
          duration: duration,
          switchInCurve: AppMotion.standard,
          switchOutCurve: AppMotion.standard,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(sizeFactor: animation, axis: Axis.horizontal, axisAlignment: -1, child: child),
          ),
          child: query.isDefault
              ? const SizedBox.shrink(key: ValueKey('no-clear'))
              : Padding(
                  key: const ValueKey('clear'),
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterPill(
                    key: const ValueKey('browse-clear'),
                    icon: Icons.close_rounded,
                    name: tr('clear', lang),
                    label: tr('clear', lang),
                    active: false,
                    showArrow: false,
                    onTap: _clearFilters,
                  ),
                ),
        ),
        _FilterPill(
          key: const ValueKey('browse-sort'),
          icon: Icons.swap_vert_rounded,
          name: tr('sort_by', lang),
          label: tr(_sortLabelKeys[query.sort] ?? 'sort_by', lang),
          active: query.sort != query.defaultSort,
          onTap: () => _pickSort(lang),
        ),
        const SizedBox(width: 8),
        _FilterPill(
          key: const ValueKey('browse-rating'),
          icon: Icons.star_rounded,
          name: tr('browse_rating', lang),
          label: query.minScore == 0 ? tr('browse_rating', lang) : _minScoreLabel(query.minScore, lang),
          active: query.minScore > 0,
          onTap: () => _pickMinScore(lang),
        ),
        const SizedBox(width: 8),
        _FilterPill(
          key: const ValueKey('browse-genres'),
          icon: Icons.local_offer_outlined,
          name: tr('browse_genres', lang),
          label: query.genres.isEmpty
              ? tr('browse_genres', lang)
              : _summary(query.genres, genreLabelKeys.keys, (genre) => genreLabel(genre, lang)),
          active: query.genres.isNotEmpty,
          onTap: () => _pickGenres(lang),
        ),
        const SizedBox(width: 8),
        _FilterPill(
          key: const ValueKey('browse-format'),
          icon: Icons.category_outlined,
          name: tr('format', lang),
          label: query.formats.isEmpty
              ? tr('format', lang)
              : _summary(query.formats, _formatOptions, (format) => _formatLabel(format, lang)),
          active: query.formats.isNotEmpty,
          onTap: () => _pickFormats(lang),
        ),
      ],
    );
  }

  /// The area under the filters; each state has its own key so changing
  /// state, or the filters, cross-fades.
  Widget _buildState(String lang) {
    final items = _paged.items;
    if (items.isEmpty) {
      if (_loadingFirst || _paged.loading || _paged.canLoadMore) {
        return const _GridSkeleton(key: ValueKey('loading'));
      }
      if (_firstFailed || _paged.failed) {
        return KeyedSubtree(key: const ValueKey('error'), child: _buildError(lang));
      }
      return KeyedSubtree(key: ValueKey('empty-${_query.filterKey}'), child: _buildEmpty(lang));
    }
    // Covers of each filter set have tags of their own: two grids are on
    // screen while they cross-fade.
    final scope = 'browse-${_query.id}-${_query.filterKey}';
    return EntranceGate(
      key: ValueKey(scope),
      trigger: scope,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: _gridPadding,
            sliver: SliverGrid.builder(
              gridDelegate: _gridDelegate,
              itemCount: items.length,
              itemBuilder: (_, i) => StaggeredEntrance(
                index: i,
                child: AnimeCard(animeData: items[i], heroScope: scope),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildFooter()),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    // Still the row's own items: the first page is on its way, or failed.
    if (_paged.lastPage == 0) {
      return LoadMoreFooter(hasMore: _loadingFirst, failed: _firstFailed, onRetry: _retryFirstPage);
    }
    return LoadMoreFooter(
      hasMore: _paged.hasNextPage,
      failed: _paged.failed,
      onRetry: () => _loadMore(retry: true),
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
              onPressed: _firstFailed ? _retryFirstPage : () => _loadMore(retry: true),
              icon: const Icon(Icons.refresh),
              label: Text(tr('retry', lang)),
            ),
          ],
        ),
      );

  Widget _buildEmpty(String lang) {
    final filtered = !_query.isDefault;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered ? Icons.filter_alt_off_outlined : Icons.search_off_rounded,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              tr(filtered ? 'browse_empty' : 'no_results', lang),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (filtered) ...[
              const SizedBox(height: 6),
              Text(
                tr('browse_empty_hint', lang),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                key: const ValueKey('browse-empty-clear'),
                // Tinted like the active filters it clears.
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: Text(tr('browse_clear_filters', lang)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A button of the filter bar: [label] with an [icon], tinted with the
/// accent while [active]. Screen readers hear [name] and then the label.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.icon,
    required this.name,
    required this.label,
    required this.active,
    required this.onTap,
    this.showArrow = true,
  });

  final IconData icon;
  final String name;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final duration = AppMotion.of(context, AppMotion.short);
    return Semantics(
      button: true,
      label: name,
      value: label == name ? null : label,
      child: Pressable(
        onTap: onTap,
        child: ExcludeSemantics(
          // The bar gives the pill its full height to tap; it looks slimmer.
          child: Align(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: duration,
              curve: AppMotion.standard,
              padding: EdgeInsets.fromLTRB(10, 7, showArrow ? 6 : 12, 7),
              decoration: BoxDecoration(
                color: active ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
                border: Border.all(
                  color: active ? cs.primary.withValues(alpha: 0.7) : Colors.grey.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: active ? cs.primary : cs.onSurface),
                duration: duration,
                curve: AppMotion.standard,
                builder: (_, color, _) => AnimatedSize(
                  duration: duration,
                  curve: AppMotion.standard,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: active ? color : color?.withValues(alpha: 0.6)),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          color: color,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      if (showArrow) ...[
                        const SizedBox(width: 2),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: color?.withValues(alpha: 0.7)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bottom sheet's handle, [title] (with [actions] beside it) and content.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child, this.actions = const []});

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: child,
              ),
            ),
          ],
        ),
      );
}

/// Pick one of [options] (value and label); the sheet closes with it.
class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({required this.title, required this.options, required this.selected});

  final String title;
  final List<(T, String)> options;
  final T selected;

  @override
  Widget build(BuildContext context) => _SheetFrame(
        title: title,
        child: Wrap(
          spacing: 8,
          children: [
            for (final (value, label) in options)
              FilterOptionChip(
                key: ValueKey('browse-option-$value'),
                label: label,
                selected: value == selected,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      );
}

/// Tick any of the [chips]; every change is reported through [onChanged].
class _MultiChoiceSheet extends StatefulWidget {
  const _MultiChoiceSheet({
    required this.title,
    required this.initial,
    required this.onChanged,
    required this.chips,
  });

  final String title;
  final Set<String> initial;
  final ValueChanged<Set<String>> onChanged;
  final Widget Function(Set<String> selected, ValueChanged<String> toggle) chips;

  @override
  State<_MultiChoiceSheet> createState() => _MultiChoiceSheetState();
}

class _MultiChoiceSheetState extends State<_MultiChoiceSheet> {
  late Set<String> _selected = widget.initial;

  void _set(Set<String> selected) {
    setState(() => _selected = selected);
    widget.onChanged(selected);
  }

  void _toggle(String value) =>
      _set(_selected.contains(value) ? _selected.difference({value}) : {..._selected, value});

  @override
  Widget build(BuildContext context) {
    final lang = context.select<SettingsProvider, String>((s) => s.language);
    return _SheetFrame(
      title: widget.title,
      actions: [
        TextButton(
          onPressed: _selected.isEmpty ? null : () => _set(const {}),
          child: Text(tr('search_reset', lang)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('apply', lang), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
      child: widget.chips(_selected, _toggle),
    );
  }
}

/// Placeholder shaped like the grid of cards.
class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: _gridPadding,
          gridDelegate: _gridDelegate,
          itemCount: 12,
          itemBuilder: (_, _) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SkeletonBox(height: double.infinity, radius: 8)),
              SizedBox(height: 6),
              SkeletonBox(height: 12),
              SizedBox(height: 4),
              SkeletonBox(width: 40, height: 10),
            ],
          ),
        ),
      );
}
