import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/anilist_service.dart';
import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../theme/app_motion.dart';
import '../utils/refresh_notifier.dart';
import '../utils/external_url.dart';
import '../utils/score_utils.dart';
import '../widgets/overlay_button.dart';
import '../widgets/skeletons.dart';
import '../widgets/detail/detail_header.dart';
import '../widgets/detail/following_section.dart';
import '../widgets/detail/media_row.dart';
import '../widgets/detail/reviews_section.dart';
import '../widgets/detail/staff_section.dart';
import '../widgets/detail/studio_links.dart';
import '../utils/fuzzy_date.dart' show FuzzyDate, formatFuzzyDate;
import '../widgets/entry_editor/entry_draft.dart' show entryStatusKey;
import '../widgets/entry_editor/entry_editor_api.dart' show loadCustomListNames;
import '../widgets/entry_editor/entry_editor_sheet.dart';
import '../widgets/motion/fade_switcher.dart';
import '../widgets/motion/pop_on_change.dart';
import '../widgets/motion/pressable.dart';
import '../widgets/motion/rounded_hero.dart';
import '../widgets/motion/stretchy_banner.dart';
import '../widgets/blurred_backdrop.dart';
import '../utils/translations.dart';
import '../providers/settings_provider.dart';
import 'character_screen.dart';

class DetailScreen extends StatefulWidget {
  final int animeId;

  /// Tag of the cover [Hero] in the list this page was opened from (see
  /// `coverHeroTag`), so that cover flies into place; null without one.
  final String? heroTag;

  /// The cover the opening list already showed, so the page can draw it
  /// from the first frame (where the flying cover lands) while it loads.
  final String? initialCoverUrl;

  const DetailScreen({super.key, required this.animeId, this.heroTag, this.initialCoverUrl});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _service = AniListService();

  /// Drives the banner's stretch and parallax.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The cover's hero tag: the opening list's, so its cover flies in.
  String get _coverTag => widget.heroTag ?? 'cover_${widget.animeId}';
  Map<String, dynamic>? _data;
  bool _customListsRequested = false;
  bool _loading = true;
  bool _togglingFav = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // The response includes the viewer's list entry and favourite, so the
  // cache key is per account. Null when signed in before the account id is
  // known: there is no cache namespace for it yet.
  String? _cacheKey(String? token, int? userId) => switch ((token, userId)) {
        (null, _) => 'anon:media:${widget.animeId}',
        (_, final int id) => ApiCache.userKey(id, 'media:${widget.animeId}'),
        _ => null,
      };

  /// Shows the cached detail instantly (when this media was opened before)
  /// and refreshes it. [force] skips the cache, e.g. right after an edit.
  Future<void> _load({bool force = false}) async {
    final auth = context.read<AuthService>();
    final cache = context.read<ApiCache>();
    final token = auth.isLoggedIn ? auth.token : null;
    final userId = auth.isLoggedIn ? (auth.user?['id'] as int?) : null;
    final key = _cacheKey(token, userId);

    void show(Map<String, dynamic>? data, {required bool isFresh}) {
      if (!mounted || data == null) return;
      setState(() {
        _data = data;
        _loading = false;
      });
      if (userId != null && token != null) {
        _preloadCustomListNames(userId, data['type'] as String? ?? 'ANIME', token);
      }
    }

    try {
      if (key == null) {
        show(await _service.getAnimeDetail(widget.animeId, token), isFresh: true);
        return;
      }
      await cache.load<Map<String, dynamic>?>(
        key: key,
        force: force,
        fetch: () => _service.getAnimeDetail(widget.animeId, token),
        decode: (json) => json as Map<String, dynamic>?,
        isValid: (data) => data != null,
        onData: show,
      );
    } on Exception catch (e) {
      debugPrint('[DetailScreen] Loading ${widget.animeId} failed: $e');
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  /// Custom list names are only needed by the edit sheet, so they load in
  /// the background instead of delaying the page; the sheet reads them from
  /// the same cache.
  void _preloadCustomListNames(int userId, String type, String token) {
    if (_customListsRequested) return;
    _customListsRequested = true;
    unawaited(loadCustomListNames(
      cache: context.read<ApiCache>(),
      service: _service,
      userId: userId,
      type: type,
      token: token,
      onData: (_) {},
    ));
  }

  /// Opens the full entry editor. It saves only what changed and keeps My
  /// List in sync; the page reloads after a save or removal.
  void _openEditor(BuildContext context) {
    final media = EditorMedia.fromMedia(_data);
    if (media == null) return;
    showEntryEditor(
      context,
      media: media,
      entry: _data?['mediaListEntry'] as Map<String, dynamic>?,
      onChanged: (_) {
        if (mounted) _load(force: true);
      },
    );
  }

  Future<void> _toggleFav() async {
    if (_togglingFav) return;
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    final wasFav = _data!['isFavourite'] == true;
    if (!wasFav) HapticFeedback.lightImpact();
    setState(() { _togglingFav = true; _data!['isFavourite'] = !wasFav; });
    final ok = await _service.toggleFavourite(
      mediaId: widget.animeId,
      isManga: _data!['type'] == 'MANGA',
      token: auth.token!,
    );
    if (mounted) {
      setState(() {
        _togglingFav = false;
        if (!ok) _data!['isFavourite'] = wasFav; // revert on failure
      });
      if (ok) {
        profileRefreshNotifier.value++;
        // Keep the cached copy in sync so the next visit doesn't flash the old state.
        final key = _cacheKey(auth.token, auth.user?['id'] as int?);
        if (key != null) unawaited(context.read<ApiCache>().write(key, _data));
      }
    }
  }

  void _copyLink() {
    final type = (_data?['type'] as String? ?? 'ANIME').toLowerCase();
    final url = 'https://anilist.co/$type/${widget.animeId}';
    final lang = context.read<SettingsProvider>().language;
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('detail_link_copied', lang)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final data = _data;
    // The page's frame (banner, cover, back button) is up from the first
    // frame, so a cover flying in from a list lands on it while the rest
    // loads; only a failed load replaces the whole page.
    return FadeSwitcher(
      child: !_loading && data == null
          ? _buildError(settings.language)
          : _buildPage(context, data, settings),
    );
  }

  Widget _buildError(String lang) => Scaffold(
        key: const ValueKey('error'),
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(tr('load_error', lang), style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _loading = true);
                  _load(force: true);
                },
                icon: const Icon(Icons.refresh),
                label: Text(tr('retry', lang)),
              ),
            ],
          ),
        ),
      );

  /// The page, with skeletons cross-fading to what [d] (null while loading)
  /// fills in. The cover stays the same widget throughout, so its flight in
  /// from a list is never cut short by the data arriving.
  Widget _buildPage(BuildContext context, Map<String, dynamic>? d, SettingsProvider settings) {
    // Keyed so a failed load cross-fades with the whole page. The page uses
    // the app's accent colour, like every other screen.
    return KeyedSubtree(
      key: const ValueKey('page'),
      child: Scaffold(
        body: Stack(
          children: [
            CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DetailHeader(
                        banner: StretchyBanner(
                          controller: _scroll,
                          child: FadeSwitcher(child: _buildBanner(context, d)),
                        ),
                        cover: _buildCover(context, d),
                        info: FadeSwitcher(
                          child: d == null ? const DetailInfoSkeleton() : _buildInfo(d, settings),
                        ),
                      ),
                      FadeSwitcher(
                        child: d == null ? const DetailBodySkeleton() : _buildBody(context, d, settings),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _buildOverlayButtons(context, d, settings.language),
          ],
        ),
      ),
    );
  }

  /// The header background. From the first frame it is the cover the page
  /// opened with, blurred (the list already decoded it), so a cover flying
  /// in never lands on an empty band; the real banner then fades in over it
  /// once downloaded (at once when it's cached). It stays one widget while
  /// loading and after, so nothing is swapped. Without any cover yet, a
  /// shimmer.
  Widget _buildBanner(BuildContext context, Map<String, dynamic>? d) {
    final surface = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    final cover = widget.initialCoverUrl ?? (d?['coverImage']?['large'] as String?);
    final banner = d?['bannerImage'] as String?;
    if (cover == null && banner == null) {
      return d == null ? const Skeleton(child: SkeletonBox(height: DetailHeader.bannerHeight, radius: 0)) : surface;
    }
    return Stack(
      key: const ValueKey('banner'),
      fit: StackFit.expand,
      children: [
        if (cover != null)
          BlurredBackdrop(url: cover, decodeWidth: DetailCoverImage.previewCacheWidth)
        else
          surface,
        if (banner != null)
          CachedNetworkImage(
            imageUrl: banner,
            fit: BoxFit.cover,
            // Banners are ~1900 px wide; decode them at the screen's width.
            memCacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round(),
            fadeInDuration: AppMotion.of(context, AppMotion.long),
            fadeOutDuration: Duration.zero,
            placeholder: (_, _) => const SizedBox.shrink(),
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
      ],
    );
  }

  /// The cover, in the hero the opening list's cover flies into: the list's
  /// cover at first, sharpened by the full-size one once [d] has loaded.
  Widget _buildCover(BuildContext context, Map<String, dynamic>? d) {
    final full = d == null ? null : (d['coverImage']?['extraLarge'] ?? d['coverImage']?['large']) as String?;
    // Always tappable (doing nothing without a cover yet): adding the
    // gesture later would rebuild the hero mid-flight.
    return Pressable(
      onTap: () {
        final url = full ?? widget.initialCoverUrl;
        if (url != null) _openCover(context, url);
      },
      child: RoundedHero(
        tag: _coverTag,
        borderRadius: DetailHeader.coverRadius,
        child: DetailCoverImage(previewUrl: widget.initialCoverUrl, url: full),
      ),
    );
  }

  /// Title, studio, next episode and the score and ranking stats.
  Widget _buildInfo(Map<String, dynamic> d, SettingsProvider settings) {
    final lang = settings.language;
    final title = settings.resolveTitle(d['title'] as Map<String, dynamic>?);
    final score = d['averageScore'] as int?;
    final nextAiring = d['nextAiringEpisode'] as Map<String, dynamic>?;
    final rankings = (d['rankings'] as List? ?? []).cast<Map<String, dynamic>>();
    final studios = (d['studios']?['nodes'] as List? ?? []).cast<Map<String, dynamic>>();
    final hasAnimationStudio = studios.any((s) => s['isAnimationStudio'] == true);
    final highestRated = _topRanking(rankings, 'RATED');
    final mostPopular = _topRanking(rankings, 'POPULAR');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (hasAnimationStudio) ...[
                const SizedBox(height: 6),
                StudioLinks(
                  studios: studios,
                  isAnimationStudio: true,
                  alignment: WrapAlignment.center,
                ),
              ],
              if (nextAiring != null) ...[
                const SizedBox(height: 8),
                Text(
                  trf('detail_episode_airs_in', lang, {
                    'n': '${nextAiring['episode']}',
                    'time': _airingCountdown(nextAiring['airingAt'] as int, lang),
                  }),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        IntrinsicHeight(
          child: Row(
            children: [
              _statCell(tr('detail_average_score', lang),
                  score != null ? '$score%' : '—',
                  score != null && score >= 70 ? Colors.green : Colors.grey),
              if (highestRated != null) ...[
                _vDivider(),
                _statCell(tr('detail_highest_rated', lang), '#${highestRated['rank']}', null,
                    sub: _rankingSub(highestRated, lang)),
              ],
              if (mostPopular != null) ...[
                _vDivider(),
                _statCell(tr('detail_most_popular', lang), '#${mostPopular['rank']}', null,
                    sub: _rankingSub(mostPopular, lang)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// The all-time [type] ranking, else the best seasonal or yearly one.
  Map<String, dynamic>? _topRanking(List<Map<String, dynamic>> rankings, String type) {
    final allTime = rankings.where((r) => r['type'] == type && r['allTime'] == true);
    if (allTime.isNotEmpty) return allTime.first;
    final others = rankings.where((r) => r['type'] == type && r['allTime'] != true).toList()
      ..sort((a, b) => (a['rank'] as int).compareTo(b['rank'] as int));
    return others.isEmpty ? null : others.first;
  }

  /// Everything under the header, from the list buttons down.
  Widget _buildBody(BuildContext context, Map<String, dynamic> d, SettingsProvider settings) {
    final lang = settings.language;
    final popularity = d['popularity'] as int?;
    final favourites = d['favourites'] as int?;
    final trending = d['trending'] as int?;
    final isManga = d['type'] == 'MANGA';
    final episodes = d['episodes'] as int?;
    final chapters = d['chapters'] as int?;
    final volumes = d['volumes'] as int?;
    final progressTotal = isManga ? chapters : episodes;
    final progressUnit = tr(isManga ? 'detail_unit_ch' : 'detail_unit_ep', lang).toUpperCase();
    final duration = d['duration'] as int?;
    final format = d['format'] as String?;
    final genres = (d['genres'] as List? ?? []).cast<String>();
    final description = (d['description'] ?? '').replaceAll(RegExp(r'<[^>]*>'), '') as String;
    final tags = (d['tags'] as List? ?? []).cast<Map<String, dynamic>>();
    final relations = (d['relations']?['edges'] as List? ?? []).cast<Map<String, dynamic>>();
    final characters = (d['characters']?['edges'] as List? ?? []).cast<Map<String, dynamic>>();
    final recommendations = [
      for (final node in (d['recommendations']?['nodes'] as List? ?? []).cast<Map<String, dynamic>>())
        ?_recommendationItem(node, settings),
    ];
    final trailer = d['trailer'] as Map<String, dynamic>?;
    final externalLinks = (d['externalLinks'] as List? ?? []).cast<Map<String, dynamic>>();
    final streamingEps = (d['streamingEpisodes'] as List? ?? []).cast<Map<String, dynamic>>();
    final synonyms = (d['synonyms'] as List? ?? []).cast<String>();
    final studios = (d['studios']?['nodes'] as List? ?? []).cast<Map<String, dynamic>>();
    final hasProducers = studios.any((s) => s['isAnimationStudio'] != true);

    final listEntry = d['mediaListEntry'] as Map<String, dynamic>?;
    final inList = listEntry != null;
    final listStatus = listEntry?['status'] as String? ?? 'PLANNING';
    final listProgress = (listEntry?['progress'] as num?)?.toInt() ?? 0;
    final listScore = (listEntry?['score'] as num?)?.toDouble() ?? 0;

    final startStr = formatFuzzyDate(FuzzyDate.fromJson(d['startDate']), lang);
    final endStr = formatFuzzyDate(FuzzyDate.fromJson(d['endDate']), lang);
    final airingRange = [startStr, endStr].where((s) => s.isNotEmpty).join(' - ');

    final season = d['season'] as String?;
    final seasonYear = d['seasonYear'] as int?;
    final seasonStr = season != null && seasonYear != null
        ? _seasonYear(season, seasonYear, lang) : null;

    final totalDuration = (episodes != null && duration != null) ? episodes * duration : null;
    final remaining = (episodes != null && duration != null)
        ? (episodes - listProgress) * duration : null;
    final scoreFormat = scoreFormatOf(context.select<AuthService, Map<String, dynamic>?>((a) => a.user));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),

        // ── Action buttons ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _actionBtn(
                context,
                inList
                    ? tr(entryStatusKey(listStatus, manga: isManga), lang).toUpperCase()
                    : tr('add_to_list', lang).toUpperCase(),
                icon: inList ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                sublabel: tr('status', lang).toUpperCase(),
                onTap: () => _openEditor(context),
              ),
              const SizedBox(width: 8),
              _actionBtn(
                context,
                progressTotal != null
                    ? '$listProgress / $progressTotal $progressUnit'
                    : '$listProgress $progressUnit',
                icon: Icons.play_circle_outline_rounded,
                sublabel: tr('progress', lang).toUpperCase(),
                onTap: () => _openEditor(context),
              ),
              const SizedBox(width: 8),
              _actionBtn(
                context,
                listScore == 0 ? tr('detail_not_scored', lang) : formatScore(listScore, scoreFormat),
                icon: listScore == 0 ? Icons.star_outline_rounded : Icons.star_rounded,
                sublabel: tr('detail_score', lang),
                onTap: () => _openEditor(context),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        const Divider(height: 1),

        // ── Summary ──
        if (description.isNotEmpty) ...[
          _SummarySection(description: description),
          const Divider(height: 1),
        ],

        // ── Series Info grid ──
        _sectionPad(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(tr('detail_series_info', lang)),
            const SizedBox(height: 12),
            _infoGrid([
              if (format != null) _InfoItem(tr('detail_type', lang), _formatLabel(format, lang)),
              if (airingRange.isNotEmpty) _InfoItem(tr(isManga ? 'detail_published' : 'detail_airing', lang), airingRange),
              if (episodes != null) _InfoItem(tr('detail_episodes', lang), '$episodes'),
              if (chapters != null) _InfoItem(tr('detail_chapters', lang), '$chapters'),
              if (volumes != null) _InfoItem(tr('detail_volumes', lang), '$volumes'),
              if (duration != null) _InfoItem(tr('detail_runtime', lang), trf('detail_per_episode', lang, {'time': _durationStr(duration, lang)})),
              if (totalDuration != null) _InfoItem(tr('detail_total_duration', lang), _durationStr(totalDuration, lang)),
              if (remaining != null && remaining > 0) _InfoItem(tr('detail_time_remaining', lang), _durationStr(remaining, lang)),
              if (seasonStr != null) _InfoItem(tr('detail_season', lang), seasonStr),
              if (popularity != null) _InfoItem(tr('popularity', lang).toUpperCase(), trf('detail_on_user_lists', lang, {'n': _fmt(popularity)})),
              if (favourites != null) _InfoItem(tr('detail_favorites', lang), _fmt(favourites)),
              if (trending != null) _InfoItem(tr('trending_sort', lang).toUpperCase(), trf('detail_trending_updates', lang, {'n': trending})),
            ]),
          ],
        )),

        // ── Titles ──
        _sectionPad(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(tr('detail_titles', lang)),
            const SizedBox(height: 10),
            if (d['title']?['romaji'] != null) _titleRow(tr('detail_title_romaji', lang), d['title']['romaji'] as String),
            if (d['title']?['english'] != null) _titleRow(tr('detail_title_english', lang), d['title']['english'] as String),
            if (d['title']?['native'] != null) _titleRow(tr('detail_title_native', lang), d['title']['native'] as String),
            if (synonyms.isNotEmpty) ...[
              const SizedBox(height: 4),
              _titleRow(tr('detail_other_names', lang), synonyms.join('\n')),
            ],
          ],
        )),
        const Divider(height: 1),

        // ── Tags ──
        if (tags.isNotEmpty) ...[
          _TagsSection(tags: tags),
          const Divider(height: 1),
        ],

        // ── Genres ──
        if (genres.isNotEmpty) ...[
          _sectionPad(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(tr('detail_genres', lang)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: genres.map((g) => _chip(context, g)).toList(),
              ),
            ],
          )),
          const Divider(height: 1),
        ],

        // ── Producers ──
        if (hasProducers) ...[
          _sectionPad(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(tr('detail_producers', lang)),
              const SizedBox(height: 10),
              StudioLinks(studios: studios, isAnimationStudio: false),
            ],
          )),
          const Divider(height: 1),
        ],

        // ── Relations ──
        if (relations.isNotEmpty) ...[
          _sectionPad(_sectionTitle(tr('detail_relations', lang))),
          DetailMediaRow(
            heroScope: 'detail-${widget.animeId}-relations',
            items: [for (final edge in relations) _relationItem(edge, settings)],
            onOpen: _openMedia,
          ),
          const Divider(height: 1),
        ],

        // ── Characters ──
        if (characters.isNotEmpty) ...[
          _sectionPad(_sectionTitle(tr('characters', lang).toUpperCase())),
          _CharactersSection(
            characters: characters,
            onTap: (id, name, img) => Navigator.push(context,
                MaterialPageRoute(builder: (_) => CharacterScreen(
                    characterId: id, name: name, imageUrl: img))),
          ),
          const Divider(height: 1),
        ],

        // ── Staff ── (brings its own title and divider; hides when empty)
        StaffSection(edges: (d['staff']?['edges'] as List?) ?? const []),

        // ── Recommended ──
        if (recommendations.isNotEmpty) ...[
          _sectionPad(_sectionTitle(tr('detail_recommended', lang))),
          DetailMediaRow(
            heroScope: 'detail-${widget.animeId}-recommended',
            height: 195,
            items: recommendations,
            onOpen: _openMedia,
          ),
          const Divider(height: 1),
        ],

        // ── Following ── (hides itself when logged out or empty)
        FollowingSection(mediaId: widget.animeId, isManga: isManga),

        // ── Trailer ──
        if (trailer != null && trailer['site'] == 'youtube') ...[
          _TrailerSection(
            trailerId: trailer['id'] as String,
            onOpenUrl: _openUrl,
          ),
          const Divider(height: 1),
        ],

        // ── Episodes ──
        if (streamingEps.isNotEmpty) ...[
          _StreamingEpisodesSection(
            episodes: streamingEps,
            onOpenUrl: _openUrl,
          ),
          const Divider(height: 1),
        ],

        // ── Reviews ── (hides itself when there are none)
        ReviewsSection(mediaId: widget.animeId),

        // ── External links ──
        if (externalLinks.isNotEmpty)
          _ExternalLinksSection(links: externalLinks, onOpenUrl: _openUrl),

        const SizedBox(height: 32),
      ],
    );
  }

  /// Back, and once the page has loaded share, favourite and edit, over the
  /// banner (44px touch targets around 36px circles, so offsets are 4px
  /// smaller than the visible spacing).
  Widget _buildOverlayButtons(BuildContext context, Map<String, dynamic>? d, String lang) {
    final isFav = d?['isFavourite'] == true;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 2,
      left: 8,
      right: 8,
      child: Row(
        children: [
          overlayBtn(
            icon: Icons.arrow_back,
            tooltip: tr('tooltip_back', lang),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          FadeSwitcher(
            child: d == null
                ? const SizedBox(key: ValueKey('loading'), height: 44)
                : Row(
                    key: const ValueKey('actions'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      overlayBtn(
                        icon: Icons.ios_share_rounded,
                        tooltip: tr('tooltip_share', lang),
                        onPressed: _copyLink,
                      ),
                      // Pops when it becomes a favourite, not when it stops.
                      PopOnChange(
                        value: isFav,
                        when: (value) => value == true,
                        child: overlayBtn(
                          icon: isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav ? Colors.red : Colors.white,
                          tooltip: tr('tooltip_favourite', lang),
                          onPressed: _toggleFav,
                        ),
                      ),
                      overlayBtn(
                        icon: Icons.more_horiz,
                        tooltip: tr('tooltip_edit_entry', lang),
                        onPressed: () => _openEditor(context),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// [media]'s title in the user's title language (English, Romaji or
  /// Native), like the page's own title.
  static String _titleOf(Map<String, dynamic> media, SettingsProvider settings) {
    final title = media['title'];
    return settings.resolveTitle(title is Map<String, dynamic> ? title : null);
  }

  DetailMediaItem _relationItem(Map<String, dynamic> edge, SettingsProvider settings) {
    final node = edge['node'] as Map<String, dynamic>? ?? {};
    return DetailMediaItem(
      id: node['id'] as int?,
      title: _titleOf(node, settings),
      coverUrl: node['coverImage']?['large'] as String?,
      subtitle: Text(
        _relationLabel(edge['relationType'] as String? ?? '', settings.language),
        style: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
    );
  }

  /// Null when AniList sent the recommendation without its media.
  DetailMediaItem? _recommendationItem(Map<String, dynamic> node, SettingsProvider settings) {
    final rec = node['mediaRecommendation'] as Map<String, dynamic>?;
    if (rec == null) return null;
    final rating = node['rating'] as int? ?? 0;
    return DetailMediaItem(
      id: rec['id'] as int?,
      title: _titleOf(rec, settings),
      coverUrl: rec['coverImage']?['large'] as String?,
      subtitle: Row(children: [
        const Icon(Icons.thumb_up_outlined, size: 10, color: Colors.grey),
        const SizedBox(width: 3),
        Text('$rating', style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    );
  }

  String _relationLabel(String s, String lang) => switch (s) {
    'PREQUEL' => tr('detail_relation_prequel', lang),
    'SEQUEL' => tr('detail_relation_sequel', lang),
    'SIDE_STORY' => tr('detail_relation_side_story', lang),
    'PARENT' => tr('detail_relation_parent', lang),
    'ALTERNATIVE' => tr('detail_relation_alternative', lang),
    'SUMMARY' => tr('detail_relation_summary', lang),
    'SPIN_OFF' => tr('detail_relation_spin_off', lang),
    'ADAPTATION' => tr('detail_relation_adaptation', lang),
    'SOURCE' => tr('detail_relation_source', lang),
    'CHARACTER' => tr('detail_relation_character', lang),
    _ => s,
  };

  /// Opens another media from the Relations or Recommended rows, its cover
  /// flying from the row.
  void _openMedia(DetailMediaItem item, String heroTag) {
    final id = item.id;
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(animeId: id, heroTag: heroTag, initialCoverUrl: item.coverUrl),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _statCell(String label, String value, Color? valueColor, {String? sub}) =>
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: valueColor)),
            if (sub != null)
              Text(sub, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      );

  Widget _vDivider() => Container(
      width: 1, height: 40, color: Theme.of(context).colorScheme.outline);

  Widget _actionBtn(BuildContext context, String label, {
    required VoidCallback onTap,
    required IconData icon,
    required String sublabel,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: cs.primary),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
              const SizedBox(height: 2),
              Text(sublabel,
                  style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurface.withValues(alpha: 0.45),
                      letterSpacing: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionPad(Widget child) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), child: child);

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: Colors.grey, letterSpacing: 0.5));

  Widget _infoGrid(List<_InfoItem> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final a = items[i];
      final b = i + 1 < items.length ? items[i + 1] : null;
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _infoCell(a.label, a.value)),
          if (b != null) Expanded(child: _infoCell(b.label, b.value))
          else const Expanded(child: SizedBox()),
        ],
      ));
      if (i + 2 < items.length) rows.add(const SizedBox(height: 12));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _infoCell(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      );

  Widget _titleRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );

  Widget _chip(BuildContext context, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      );

  String _airingCountdown(int airingAt, String lang) {
    final diff = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000).difference(DateTime.now());
    if (diff.inDays > 0) {
      return trf('detail_countdown_dh', lang, {'d': diff.inDays, 'h': diff.inHours % 24});
    }
    if (diff.inHours > 0) {
      return trf('detail_countdown_hm', lang, {'h': diff.inHours, 'm': diff.inMinutes % 60});
    }
    return trf('detail_countdown_m', lang, {'m': diff.inMinutes});
  }

  String _durationStr(int minutes, String lang) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final hourWord = h == 1 ? tr('hour', lang) : tr('hours', lang);
    final minWord = m == 1 ? tr('minute', lang) : tr('minutes', lang);
    if (h == 0) return '$m $minWord';
    if (m == 0) return '$h $hourWord';
    final and = tr('and', lang);
    return '$h $hourWord${and.isNotEmpty ? ' $and' : ''} $m $minWord';
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1).replaceAll('.0', '')}K';
    return '$n';
  }

  // TV, OVA and ONA read the same in every language, so they fall through.
  String _formatLabel(String f, String lang) => switch (f) {
    'MOVIE' => tr('movie', lang),
    'SPECIAL' => tr('special', lang),
    'MUSIC' => tr('detail_format_music', lang),
    'TV_SHORT' => tr('detail_format_tv_short', lang),
    'MANGA' => tr('source_manga', lang),
    'NOVEL' => tr('source_light_novel', lang),
    'ONE_SHOT' => tr('detail_format_one_shot', lang),
    _ => f,
  };

  String _seasonLabel(String s, String lang) => switch (s) {
    'WINTER' => tr('detail_season_winter', lang),
    'SPRING' => tr('detail_season_spring', lang),
    'SUMMER' => tr('detail_season_summer', lang),
    'FALL' => tr('detail_season_fall', lang),
    _ => s,
  };

  String _seasonYear(String season, Object year, String lang) =>
      trf('detail_season_year', lang, {'season': _seasonLabel(season, lang), 'year': year});

  String _rankingSub(Map<String, dynamic>? r, String lang) {
    final allTime = tr('detail_all_time', lang);
    if (r == null) return allTime;
    if (r['allTime'] == true) return allTime;
    final season = r['season'] as String?;
    final year = r['year'];
    if (season != null && year != null) return _seasonYear(season, year, lang);
    if (year != null) return '$year';
    return allTime;
  }

  void _openCover(BuildContext context, String imageUrl) {
    Navigator.push(context, PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, _, _) => _CoverViewer(tag: _coverTag, imageUrl: imageUrl),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ));
  }

  Future<void> _openUrl(String url) => openExternalUrl(url);
}

// ── Extracted section widgets ─────────────────────────────────────────────

class _SummarySection extends StatefulWidget {
  final String description;
  const _SummarySection({required this.description});
  @override
  State<_SummarySection> createState() => _SummarySectionState();
}

class _SummarySectionState extends State<_SummarySection> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('detail_summary', lang),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: Colors.grey, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          // Opens and closes smoothly instead of jumping.
          AnimatedSize(
            duration: AppMotion.of(context, AppMotion.medium),
            curve: AppMotion.standard,
            alignment: AlignmentDirectional.topStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Text(
                    widget.description,
                    style: const TextStyle(color: Colors.grey, height: 1.6, fontSize: 13),
                    maxLines: _expanded ? null : 4,
                    overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                ),
                if (!_expanded)
                  GestureDetector(
                    onTap: () => setState(() => _expanded = true),
                    child: Builder(builder: (ctx) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(tr('detail_read_more', lang),
                          style: TextStyle(color: Theme.of(ctx).colorScheme.primary, fontSize: 12)),
                    )),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagsSection extends StatefulWidget {
  final List<Map<String, dynamic>> tags;
  const _TagsSection({required this.tags});
  @override
  State<_TagsSection> createState() => _TagsSectionState();
}

class _TagsSectionState extends State<_TagsSection> {
  bool _showAll = false;
  bool _showSpoilers = false;

  Widget _tagChip(String name, bool spoiler) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: spoiler
              ? Colors.orange.withValues(alpha: 0.15)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: spoiler ? Border.all(color: Colors.orange.withValues(alpha: 0.4)) : null,
        ),
        child: Text(name,
            style: TextStyle(fontSize: 11, color: spoiler ? Colors.orange : null)),
      );

  Widget _smallBtn(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final spoilerCount = widget.tags.where((t) => t['isMediaSpoiler'] == true).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tr('detail_tags', lang),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: Colors.grey, letterSpacing: 0.5)),
              ),
              if (spoilerCount > 0)
                _smallBtn(
                  _showSpoilers
                      ? tr('detail_hide_spoiler_tags', lang)
                      : trf('detail_show_spoiler_tags', lang, {'n': spoilerCount}),
                  () => setState(() => _showSpoilers = !_showSpoilers),
                ),
              const SizedBox(width: 8),
              _smallBtn(
                _showAll
                    ? tr('detail_show_less', lang)
                    : trf('detail_show_all_tags', lang, {'n': widget.tags.length}),
                () => setState(() => _showAll = !_showAll),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSize(
            duration: AppMotion.of(context, AppMotion.medium),
            curve: AppMotion.standard,
            alignment: AlignmentDirectional.topStart,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.tags
                  .where((t) => _showAll || t['isMediaSpoiler'] != true || _showSpoilers)
                  .take(_showAll ? 999 : 9)
                  .map((t) => _tagChip(t['name'] as String, t['isMediaSpoiler'] == true))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CharactersSection extends StatelessWidget {
  final List<Map<String, dynamic>> characters;
  final void Function(int id, String name, String? imageUrl) onTap;
  const _CharactersSection({required this.characters, required this.onTap});

  String _roleLabel(String role, String lang) => switch (role) {
    'MAIN' => tr('detail_role_main', lang),
    'SUPPORTING' => tr('detail_role_supporting', lang),
    'BACKGROUND' => tr('detail_role_background', lang),
    _ => role.toLowerCase(),
  };

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    final fadeIn = AppMotion.of(context, AppMotion.short);
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: characters.length,
        itemBuilder: (_, i) {
          final edge = characters[i];
          final node = edge['node'] as Map<String, dynamic>? ?? {};
          final charId = node['id'] as int?;
          final name = node['name']?['full'] as String? ?? '';
          final img = node['image']?['medium'] as String?;
          final role = _roleLabel(edge['role'] as String? ?? '', lang);
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Pressable(
              onTap: charId != null ? () => onTap(charId, name, img) : null,
              child: SizedBox(
                width: 80,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 80,
                        height: 110,
                        child: img != null
                            ? CachedNetworkImage(
                                imageUrl: img,
                                fit: BoxFit.cover,
                                memCacheWidth: 160,
                                fadeInDuration: fadeIn,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, _) => placeholder,
                                errorWidget: (_, _, _) => placeholder,
                              )
                            : placeholder,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
                    Text(role, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TrailerSection extends StatelessWidget {
  final String trailerId;
  final Future<void> Function(String url) onOpenUrl;
  const _TrailerSection({required this.trailerId, required this.onOpenUrl});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('detail_trailer', lang),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: Colors.grey, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Pressable(
            // A full-width card only needs a hint of a press.
            pressedScale: 0.98,
            onTap: () => onOpenUrl('https://www.youtube.com/watch?v=$trailerId'),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: 'https://img.youtube.com/vi/$trailerId/hqdefault.jpg',
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    fadeInDuration: AppMotion.of(context, AppMotion.short),
                    fadeOutDuration: Duration.zero,
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, size: 36, color: Colors.black),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamingEpisodesSection extends StatelessWidget {
  final List<Map<String, dynamic>> episodes;
  final Future<void> Function(String url) onOpenUrl;
  const _StreamingEpisodesSection({required this.episodes, required this.onOpenUrl});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final site = episodes.isNotEmpty ? episodes.first['site'] as String? : null;
    final title = site != null
        ? trf('detail_streaming_episodes_on', lang, {'site': site.toUpperCase()})
        : tr('detail_streaming_episodes', lang);
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    final fadeIn = AppMotion.of(context, AppMotion.short);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: Colors.grey, letterSpacing: 0.5)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            itemCount: episodes.length,
            itemBuilder: (_, i) {
              final ep = episodes[i];
              final thumb = ep['thumbnail'] as String?;
              final epTitle = ep['title'] as String? ?? '';
              final url = ep['url'] as String?;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Pressable(
                  onTap: url != null ? () => onOpenUrl(url) : null,
                  child: SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 160,
                            height: 110,
                            child: thumb != null
                                ? CachedNetworkImage(
                                    imageUrl: thumb,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 320,
                                    fadeInDuration: fadeIn,
                                    fadeOutDuration: Duration.zero,
                                    placeholder: (_, _) => placeholder,
                                    errorWidget: (_, _, _) => placeholder,
                                  )
                                : placeholder,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(epTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExternalLinksSection extends StatelessWidget {
  final List<Map<String, dynamic>> links;
  final Future<void> Function(String url) onOpenUrl;
  const _ExternalLinksSection({required this.links, required this.onOpenUrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lang = context.watch<SettingsProvider>().language;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('detail_external_links', lang),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: Colors.grey, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: links.map((link) {
              final site = link['site'] as String? ?? '';
              final url = link['url'] as String? ?? '';
              return GestureDetector(
                onTap: () => onOpenUrl(url),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cs.outline, width: 1),
                  ),
                  child: Text(site,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────

class _InfoItem {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);
}

// ── Full-screen cover viewer ──────────────────────────────────────────────

class _CoverViewer extends StatelessWidget {
  final String tag;
  final String imageUrl;
  const _CoverViewer({required this.tag, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Hero(
            tag: tag,
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
