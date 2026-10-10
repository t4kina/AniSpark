import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/api_cache.dart';
import '../services/people_api.dart';
import '../utils/translations.dart';
import '../widgets/detail/load_error_view.dart';
import '../widgets/detail/section_title.dart';
import '../widgets/people/info_pill.dart';
import '../widgets/people/media_cover_tile.dart';
import '../widgets/people/paged_items.dart';
import '../widgets/people/people_labels.dart';
import '../widgets/people/people_routes.dart';
import '../widgets/skeletons.dart';

/// A studio's page: its productions as a cover grid, most popular first,
/// those it was the main studio of before the rest, loading more on scroll.
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, required this.studioId, this.name, this.api});

  final int studioId;

  /// Shown until the page loads (from the link that opened it).
  final String? name;

  /// Replaces the AniList API, for tests.
  final PeopleApi? api;

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> with PagedLoading {
  // Public and slow-changing, so a recent copy isn't refetched.
  static const _maxAge = Duration(hours: 6);
  // Starts loading the next page this close to the end of the grid.
  static const _loadMoreExtent = 600.0;

  late final PeopleApi _api = widget.api ?? PeopleApi();
  final _scroll = ScrollController();

  StudioDetail? _studio;
  bool _loading = true;

  /// Media it was the main studio of, then the rest (shown once [_main]
  /// has no more pages).
  PagedItems<MediaRef> _main = const PagedItems();
  PagedItems<MediaRef> _other = const PagedItems();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(loadMoreIfNearEnd);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static StudioDetail _decode(Object? json) =>
      StudioDetail.fromJson(json) ?? (throw const FormatException('Not a cached studio'));

  Future<void> _load({bool force = false}) async {
    final studioId = widget.studioId;
    try {
      await context.read<ApiCache>().load<StudioDetail>(
            key: 'studio:$studioId',
            fetch: () => _api.getStudio(studioId),
            decode: _decode,
            onData: (studio, {required isFresh}) {
              if (!mounted) return;
              resetPaging();
              setState(() {
                _studio = studio;
                _main = PagedItems.firstPage(studio.main.media, hasNextPage: studio.main.hasNextPage);
                _other = PagedItems.firstPage(studio.other.media, hasNextPage: studio.other.hasNextPage);
              });
              WidgetsBinding.instance.addPostFrameCallback((_) => loadMoreIfNearEnd());
            },
            maxAge: _maxAge,
            force: force,
          );
    } on Exception catch (e) {
      debugPrint('[StudioScreen] Loading studio $studioId failed: $e');
      if (force && mounted && _studio != null) _showLoadError();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _retry() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _refresh() => _load(force: true);

  void _showLoadError() {
    final lang = context.read<SettingsProvider>().language;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('load_error', lang))));
  }

  /// The list that grows next: the main productions until they run out.
  bool get _loadingMain => _main.hasNextPage;

  @override
  void loadMoreIfNearEnd() {
    if (!mounted || !_scroll.hasClients || _studio == null) return;
    if (_scroll.position.extentAfter > _loadMoreExtent) return;
    final list = _loadingMain ? _main : _other;
    if (list.canLoadMore) _loadMore(isMain: _loadingMain);
  }

  void _loadMore({required bool isMain, bool retry = false}) => unawaited(loadNextPage<MediaRef>(
        read: () => isMain ? _main : _other,
        write: (value) {
          if (isMain) {
            _main = value;
          } else {
            _other = value;
          }
        },
        fetch: (page) async {
          final result = await _api.getStudioMedia(widget.studioId, isMain: isMain, page: page);
          return (result.media, result.hasNextPage);
        },
        merge: appendMedia,
        debugLabel: 'StudioScreen ${isMain ? 'main' : 'other'} media of ${widget.studioId}',
        retry: retry,
      ));

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final studio = _studio;
    final name = studio != null && studio.name.isNotEmpty ? studio.name : widget.name ?? '';
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        // Nothing to refresh until the page has loaded (retry covers that).
        notificationPredicate: (notification) => _studio != null && notification.depth == 0,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.medium(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: tr('tooltip_back', lang),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ..._content(studio, lang),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(StudioDetail? studio, String lang) {
    if (studio == null) {
      return [
        if (_loading)
          const SliverToBoxAdapter(child: _GridSkeleton())
        else
          SliverFillRemaining(hasScrollBody: false, child: LoadErrorView(onRetry: _retry)),
      ];
    }
    final mainIds = {for (final media in _main.items) media.id};
    final others = _main.hasNextPage
        ? const <MediaRef>[]
        : [for (final media in _other.items) if (!mainIds.contains(media.id)) media];
    // Titles only help when the grid has both groups.
    final showsTitles = _main.items.isNotEmpty && _other.items.isNotEmpty;
    final active = _loadingMain ? _main : _other;
    final favourites = studio.favourites;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoPill(
                icon: studio.isAnimationStudio ? Icons.movie_filter_outlined : Icons.business_outlined,
                label: tr(studio.isAnimationStudio ? 'studio_animation_studio' : 'studio_producer', lang),
              ),
              if (favourites != null && favourites > 0)
                Semantics(
                  label: trf('staff_favourites', lang, {'n': favourites}),
                  excludeSemantics: true,
                  child: InfoPill(
                    icon: Icons.favorite_rounded,
                    iconColor: Colors.redAccent,
                    label: compactCount(favourites),
                  ),
                ),
            ],
          ),
        ),
      ),
      if (_main.items.isEmpty && _other.items.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text(tr('nothing_here', lang), style: const TextStyle(color: Colors.grey))),
        ),
      if (showsTitles && _main.items.isNotEmpty) _title(tr('studio_main_productions', lang)),
      _grid(_main.items, lang),
      if (others.isNotEmpty) ...[
        if (showsTitles) _title(tr('studio_other_productions', lang)),
        _grid(others, lang),
      ],
      SliverToBoxAdapter(
        child: LoadMoreFooter(
          hasMore: _main.hasNextPage || _other.hasNextPage,
          failed: active.failed,
          onRetry: () => _loadMore(isMain: _loadingMain, retry: true),
        ),
      ),
      SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom)),
    ];
  }

  Widget _title(String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: DetailSectionTitle(text.toUpperCase()),
        ),
      );

  Widget _grid(List<MediaRef> media, String lang) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        sliver: SliverGrid.builder(
          gridDelegate: mediaCoverGridDelegate,
          itemCount: media.length,
          itemBuilder: (context, i) => MediaCoverTile(
            media: media[i],
            subtitle: mediaFormatAndYear(media[i], lang),
            onTap: () => openMedia(context, media[i]),
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
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          gridDelegate: mediaCoverGridDelegate,
          itemCount: 9,
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
