import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/media_list_store.dart';
import '../services/anilist_service.dart';
import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../utils/refresh_notifier.dart';
import '../utils/external_url.dart';
import '../utils/media_color.dart';
import '../utils/score_utils.dart';
import '../widgets/overlay_button.dart';
import '../widgets/skeletons.dart';
import '../utils/translations.dart';
import '../providers/settings_provider.dart';
import 'character_screen.dart';

class DetailScreen extends StatefulWidget {
  final int animeId;
  const DetailScreen({super.key, required this.animeId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _service = AniListService();
  Map<String, dynamic>? _data;
  List<String> _customListNames = [];
  bool _customListsRequested = false;
  bool _loading = true;
  bool _togglingFav = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // The response includes the viewer's list entry and favourite, so the
  // cache key is per account.
  String _cacheKey(int? userId) => userId != null
      ? ApiCache.userKey(userId, 'media:${widget.animeId}')
      : 'anon:media:${widget.animeId}';

  /// Shows the cached detail instantly (when this media was opened before)
  /// and refreshes it. [force] skips the cache, e.g. right after an edit.
  Future<void> _load({bool force = false}) async {
    final auth = context.read<AuthService>();
    final cache = context.read<ApiCache>();
    final token = auth.isLoggedIn ? auth.token : null;
    final userId = auth.isLoggedIn ? (auth.user?['id'] as int?) : null;
    try {
      await cache.load<Map<String, dynamic>?>(
        key: _cacheKey(userId),
        force: force,
        fetch: () => _service.getAnimeDetail(widget.animeId, token),
        decode: (json) => json as Map<String, dynamic>?,
        isValid: (data) => data != null,
        onData: (data, {required isFresh}) {
          if (!mounted || data == null) return;
          setState(() {
            _data = data;
            _loading = false;
          });
          if (userId != null && token != null) {
            _loadCustomListNames(userId, data['type'] as String? ?? 'ANIME', token);
          }
        },
      );
    } on Exception catch (e) {
      debugPrint('[DetailScreen] Loading ${widget.animeId} failed: $e');
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  /// Custom list names are only needed by the edit sheet, so they load in
  /// the background instead of delaying the page.
  Future<void> _loadCustomListNames(int userId, String type, String token) async {
    if (_customListsRequested) return;
    _customListsRequested = true;
    try {
      await context.read<ApiCache>().load<List<String>>(
        key: ApiCache.userKey(userId, 'customLists:$type'),
        maxAge: const Duration(hours: 1),
        fetch: () => _service.getCustomListNames(userId, type, token),
        decode: (json) => [for (final name in json as List) name as String],
        onData: (names, {required isFresh}) {
          if (mounted) setState(() => _customListNames = names);
        },
      );
    } on Exception catch (e) {
      debugPrint('[DetailScreen] Loading custom lists failed: $e');
    }
  }

  /// Refreshes the user's list of this media's type after an edit here.
  void _refreshList() {
    final auth = context.read<AuthService>();
    final userId = auth.user?['id'] as int?;
    final token = auth.token;
    if (userId == null || token == null) return;
    unawaited(context.read<MediaListStore>().load(
          _data?['type'] as String? ?? 'ANIME',
          userId: userId,
          token: token,
          force: true,
        ));
  }

  Future<void> _toggleFav() async {
    if (_togglingFav) return;
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    final wasFav = _data!['isFavourite'] == true;
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
        final userId = auth.user?['id'] as int?;
        unawaited(context.read<ApiCache>().write(_cacheKey(userId), _data));
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

  String _toAniListStatus(String local) => switch (local) {
    'watching'      => 'CURRENT',
    'completed'     => 'COMPLETED',
    'plan_to_watch' => 'PLANNING',
    'dropped'       => 'DROPPED',
    'on_hold'       => 'PAUSED',
    'rewatching'    => 'REPEATING',
    _               => 'PLANNING',
  };

  String _fromAniListStatus(String s) => switch (s) {
    'CURRENT'   => 'watching',
    'COMPLETED' => 'completed',
    'PLANNING'  => 'plan_to_watch',
    'DROPPED'   => 'dropped',
    'PAUSED'    => 'on_hold',
    'REPEATING' => 'rewatching',
    _           => 'plan_to_watch',
  };

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    if (_loading) {
      return Scaffold(
        body: Stack(
          children: [
            const DetailSkeleton(),
            Positioned(
              top: MediaQuery.of(context).padding.top + 2,
              left: 8,
              child: overlayBtn(
                icon: Icons.arrow_back,
                tooltip: tr('tooltip_back', lang),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      );
    }
    if (_data == null) {
      return Scaffold(
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
    }

    final d = _data!;

    final title = settings.resolveTitle(d['title'] as Map<String, dynamic>?);
    final cover = d['coverImage']?['extraLarge'] ?? d['coverImage']?['large'];
    final banner = d['bannerImage'] as String?;
    final score = d['averageScore'] as int?;
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
    final nextAiring = d['nextAiringEpisode'] as Map<String, dynamic>?;
    final rankings = (d['rankings'] as List? ?? []).cast<Map<String, dynamic>>();
    final tags = (d['tags'] as List? ?? []).cast<Map<String, dynamic>>();
    final relations = (d['relations']?['edges'] as List? ?? []).cast<Map<String, dynamic>>();
    final characters = (d['characters']?['edges'] as List? ?? []).cast<Map<String, dynamic>>();
    final recommendations = (d['recommendations']?['nodes'] as List? ?? []).cast<Map<String, dynamic>>();
    final trailer = d['trailer'] as Map<String, dynamic>?;
    final externalLinks = (d['externalLinks'] as List? ?? []).cast<Map<String, dynamic>>();
    final streamingEps = (d['streamingEpisodes'] as List? ?? []).cast<Map<String, dynamic>>();
    final synonyms = (d['synonyms'] as List? ?? []).cast<String>();
    final studios = (d['studios']?['nodes'] as List? ?? []).cast<Map<String, dynamic>>();
    final animationStudios = studios.where((s) => s['isAnimationStudio'] == true).map((s) => s['name'] as String).toList();
    final producers = studios.where((s) => s['isAnimationStudio'] != true).map((s) => s['name'] as String).toList();

    final listEntry = d['mediaListEntry'] as Map<String, dynamic>?;
    final inList = listEntry != null;

    String listStatus = 'plan_to_watch';
    int listProgress = 0;
    double listScore = 0;
    if (listEntry != null) {
      listStatus = _fromAniListStatus(listEntry['status'] as String? ?? 'PLANNING');
      listProgress = (listEntry['progress'] as num?)?.toInt() ?? 0;
      listScore = (listEntry['score'] as num?)?.toDouble() ?? 0;
    }

    final allTimeRated = rankings.where((r) => r['type'] == 'RATED' && r['allTime'] == true).toList();
    final allTimePopular = rankings.where((r) => r['type'] == 'POPULAR' && r['allTime'] == true).toList();
    final yearRated = rankings.where((r) => r['type'] == 'RATED' && r['allTime'] != true).toList()
      ..sort((a, b) => (a['rank'] as int).compareTo(b['rank'] as int));
    final yearPopular = rankings.where((r) => r['type'] == 'POPULAR' && r['allTime'] != true).toList()
      ..sort((a, b) => (a['rank'] as int).compareTo(b['rank'] as int));
    final highestRated = allTimeRated.isNotEmpty ? allTimeRated.first : (yearRated.isNotEmpty ? yearRated.first : null);
    final mostPopular = allTimePopular.isNotEmpty ? allTimePopular.first : (yearPopular.isNotEmpty ? yearPopular.first : null);

    final startDate = d['startDate'];
    final endDate = d['endDate'];
    final startStr = _dateStr(startDate, lang);
    final endStr = _dateStr(endDate, lang);
    final airingRange = [startStr, endStr].where((s) => s.isNotEmpty).join(' - ');

    final season = d['season'] as String?;
    final seasonYear = d['seasonYear'] as int?;
    final seasonStr = season != null && seasonYear != null
        ? _seasonYear(season, seasonYear, lang) : null;

    final totalDuration = (episodes != null && duration != null) ? episodes * duration : null;
    final watched = listProgress;
    final remaining = (episodes != null && duration != null)
        ? (episodes - watched) * duration : null;
    final scoreFormat = scoreFormatOf(context.select<AuthService, Map<String, dynamic>?>((a) => a.user));

    // The page picks up the cover's colour (made readable for the theme).
    final theme = Theme.of(context);
    final accent = mediaAccentColor(d['coverImage']?['color'] as String?, theme.brightness);
    final pageTheme = accent == null
        ? theme
        : theme.copyWith(colorScheme: theme.colorScheme.copyWith(primary: accent));

    return Theme(data: pageTheme, child: Builder(builder: (context) => Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                // ── HEADER CARD ──
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 18,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Banner image
                          SizedBox(
                            height: 200,
                            width: double.infinity,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(0),
                                topRight: Radius.circular(0),
                              ),
                              child: banner != null
                                  ? CachedNetworkImage(imageUrl: banner, fit: BoxFit.cover)
                                  : Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                            ),
                          ),
                          // Space for cover overflow below banner
                          const SizedBox(height: 80),
                          // Title + studio + airing
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                Text(title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                if (animationStudios.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(animationStudios.first,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
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
                          // Stats row
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
                      ),
                      // Gradient: banner fades into surface color
                      Positioned(
                        top: 110, left: 0, right: 0,
                        child: Container(
                          height: 90,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                                Theme.of(context).colorScheme.surface,
                              ],
                              stops: const [0.3, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Cover image straddling banner / content
                      Positioned(
                        top: 80,
                        child: GestureDetector(
                          onTap: cover != null ? () => _openCover(context, cover!) : null,
                          child: Hero(
                            tag: 'cover_${widget.animeId}',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: cover != null
                                  ? CachedNetworkImage(
                                      imageUrl: cover,
                                      width: 130,
                                      height: 190,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 260,
                                    )
                                  : Container(width: 130, height: 190,
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Action buttons ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _actionBtn(
                        context,
                        inList ? _statusLabel(listStatus, lang) : tr('add_to_list', lang).toUpperCase(),
                        icon: inList ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                        sublabel: tr('status', lang).toUpperCase(),
                        onTap: () => _showEditModal(context, listStatus, listProgress, listScore),
                      ),
                      const SizedBox(width: 8),
                      _actionBtn(
                        context,
                        progressTotal != null
                            ? '$listProgress / $progressTotal $progressUnit'
                            : '$listProgress $progressUnit',
                        icon: Icons.play_circle_outline_rounded,
                        sublabel: tr('progress', lang).toUpperCase(),
                        onTap: () => _showEditModal(context, listStatus, listProgress, listScore),
                      ),
                      const SizedBox(width: 8),
                      _actionBtn(
                        context,
                        listScore == 0 ? tr('detail_not_scored', lang) : formatScore(listScore, scoreFormat),
                        icon: listScore == 0 ? Icons.star_outline_rounded : Icons.star_rounded,
                        sublabel: tr('detail_score', lang),
                        onTap: () => _showEditModal(context, listStatus, listProgress, listScore),
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
                if (producers.isNotEmpty) ...[
                  _sectionPad(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle(tr('detail_producers', lang)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: producers.map((p) => _chip(context, p)).toList(),
                      ),
                    ],
                  )),
                  const Divider(height: 1),
                ],

                // ── Relations ──
                if (relations.isNotEmpty) ...[
                  _sectionPad(_sectionTitle(tr('detail_relations', lang))),
                  _RelationsSection(
                    relations: relations,
                    onTap: (id) => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => DetailScreen(animeId: id))),
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

                // ── Recommended ──
                if (recommendations.isNotEmpty) ...[
                  _sectionPad(_sectionTitle(tr('detail_recommended', lang))),
                  _RecommendedSection(
                    recommendations: recommendations,
                    onTap: (id) => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => DetailScreen(animeId: id))),
                  ),
                  const Divider(height: 1),
                ],

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

                // ── External links ──
                if (externalLinks.isNotEmpty)
                  _ExternalLinksSection(links: externalLinks, onOpenUrl: _openUrl),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),

          // ── Overlay buttons ── (44px touch targets around 36px circles,
          // so offsets are 4px smaller than the visible spacing)
          Positioned(
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
                overlayBtn(
                  icon: Icons.ios_share_rounded,
                  tooltip: tr('tooltip_share', lang),
                  onPressed: _copyLink,
                ),
                overlayBtn(
                  icon: d['isFavourite'] == true ? Icons.favorite : Icons.favorite_border,
                  color: d['isFavourite'] == true ? Colors.red : Colors.white,
                  tooltip: tr('tooltip_favourite', lang),
                  onPressed: _toggleFav,
                ),
                overlayBtn(
                  icon: Icons.more_horiz,
                  tooltip: tr('tooltip_edit_entry', lang),
                  onPressed: () => _showEditModal(context, listStatus, listProgress, listScore),
                ),
              ],
            ),
          ),
        ],
      ),
    )));
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

  String _dateStr(Map<String, dynamic>? d, String lang) {
    if (d == null) return '';
    final y = d['year']; final m = d['month']; final day = d['day'];
    if (y == null) return '';
    if (m == null) return '$y';
    final mStr = (m as int) >= 1 && m <= 12 ? tr('detail_month_$m', lang) : '$m';
    if (day == null) return trf('detail_date_month_year', lang, {'month': mStr, 'year': y});
    return trf('detail_date_full', lang, {'day': day, 'month': mStr, 'year': y});
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

  /// Translation key of a local list status, worded for reading on manga.
  static String _statusKey(String status, {required bool manga}) => switch (status) {
    'watching'      => manga ? 'reading' : 'watching',
    'plan_to_watch' => manga ? 'plan_to_read' : 'plan_to_watch',
    'rewatching'    => manga ? 'rereading' : 'rewatching',
    _               => status, // completed, dropped, on_hold
  };

  String _statusLabel(String s, String lang) {
    final manga = (_data?['type'] as String?) == 'MANGA';
    return tr(_statusKey(s, manga: manga), lang).toUpperCase();
  }

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
      pageBuilder: (_, _, _) => _CoverViewer(tag: 'cover_${widget.animeId}', imageUrl: imageUrl),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ));
  }

  Future<void> _openUrl(String url) => openExternalUrl(url);

  void _showEditModal(BuildContext context,
      String initialStatus, int initialProgress, double initialScore) {
    final resolvedTitle = context.read<SettingsProvider>().resolveTitle(_data!['title'] as Map<String, dynamic>?);
    final totalEps = (_data!['episodes'] ?? _data!['chapters']) as int?;
    final isManga = (_data!['type'] as String?) == 'MANGA';

    final lang = context.read<SettingsProvider>().language;
    final entryId = _data!['mediaListEntry']?['id'] as int?;
    final progressUnit = tr(isManga ? 'detail_unit_ch' : 'detail_unit_ep', lang);
    String statusText(String status) => tr(_statusKey(status, manga: isManga), lang);

    String selectedStatus = initialStatus;
    int progress = initialProgress;
    double score = initialScore;
    bool saving = false;
    String? errorText;
    final initialNotes = (_data!['mediaListEntry']?['notes'] as String?) ?? '';
    final notesController = TextEditingController(text: initialNotes);

    // Parse current custom lists from entry data
    final rawCustom = _data!['mediaListEntry']?['customLists'];
    final initialCustom = <String>{};
    if (rawCustom is Map) {
      for (final e in rawCustom.entries) {
        if (e.value == true) initialCustom.add(e.key as String);
      }
    }
    final selectedCustomLists = Set<String>.from(initialCustom);

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)))),
              Text(resolvedTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              Text(tr('status', lang), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _statusChip(ctx, statusText('watching'), 'watching', selectedStatus, (v) => setModal(() => selectedStatus = v)),
                _statusChip(ctx, statusText('completed'), 'completed', selectedStatus, (v) => setModal(() => selectedStatus = v)),
                _statusChip(ctx, statusText('plan_to_watch'), 'plan_to_watch', selectedStatus, (v) => setModal(() => selectedStatus = v)),
                _statusChip(ctx, statusText('on_hold'), 'on_hold', selectedStatus, (v) => setModal(() => selectedStatus = v)),
                _statusChip(ctx, statusText('dropped'), 'dropped', selectedStatus, (v) => setModal(() => selectedStatus = v)),
                _statusChip(ctx, statusText('rewatching'), 'rewatching', selectedStatus, (v) => setModal(() => selectedStatus = v)),
              ]),
              const SizedBox(height: 16),
              Text(tr('progress', lang), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: [
                _counterBtn(ctx, Icons.remove, () { if (progress > 0) setModal(() => progress--); }),
                const SizedBox(width: 12),
                Expanded(child: Text(totalEps != null ? '$progress / $totalEps $progressUnit' : '$progress $progressUnit',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                const SizedBox(width: 12),
                _counterBtn(ctx, Icons.add, () { if (totalEps == null || progress < totalEps) setModal(() => progress++); }),
              ]),
              const SizedBox(height: 16),
              Text(tr('score', lang), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: [
                _counterBtn(ctx, Icons.remove, () { if (score > 0) setModal(() => score = (score - 0.5).clamp(0, 10)); }),
                const SizedBox(width: 12),
                Expanded(child: Text(score == 0 ? '—' : score.toStringAsFixed(1),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                const SizedBox(width: 12),
                _counterBtn(ctx, Icons.add, () { if (score < 10) setModal(() => score = (score + 0.5).clamp(0, 10)); }),
              ]),
              if (_customListNames.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(tr('detail_custom_lists', lang), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _customListNames.map((name) {
                    final selected = selectedCustomLists.contains(name);
                    return Builder(builder: (c) => FilterChip(
                      label: Text(name, style: TextStyle(fontSize: 12, color: selected ? Colors.white : null)),
                      selected: selected,
                      selectedColor: Theme.of(c).colorScheme.primary,
                      checkmarkColor: Colors.white,
                      onSelected: (v) => setModal(() {
                        if (v) { selectedCustomLists.add(name); } else { selectedCustomLists.remove(name); }
                      }),
                    ));
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
              Text(tr('detail_notes', lang), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: tr('detail_notes_hint', lang),
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  filled: true,
                  fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 24),
              if (errorText != null) ...[
                Text(errorText ?? '', style: const TextStyle(color: Colors.red, fontSize: 12)),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: saving ? null : () async {
                    final token = context.read<AuthService>().token;
                    final messenger = ScaffoldMessenger.of(context);
                    if (token == null) {
                      setModal(() => errorText = tr('connect_anilist', lang));
                      return;
                    }
                    setModal(() { saving = true; errorText = null; });
                    final notes = notesController.text.trim();
                    final customListsChanged = selectedCustomLists.length != initialCustom.length ||
                        !selectedCustomLists.containsAll(initialCustom);
                    // Unchanged fields are left out so AniList keeps them exactly as they are.
                    final saved = await _service.saveListEntry(
                      mediaId: widget.animeId,
                      status: _toAniListStatus(selectedStatus),
                      progress: progress,
                      scoreRaw: score != initialScore ? toRawScore(score) : null,
                      notes: notes != initialNotes.trim() ? notes : null,
                      customLists: customListsChanged ? selectedCustomLists.toList() : null,
                      token: token,
                    );
                    if (saved == null) {
                      if (sheetContext.mounted) {
                        setModal(() { saving = false; errorText = tr('save_failed', lang); });
                      }
                      return;
                    }
                    if (!mounted) return;
                    _load(force: true);
                    _refreshList();
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    messenger.showSnackBar(SnackBar(content: Text(trf('detail_saved', lang, {'title': resolvedTitle}))));
                  },
                  child: saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(tr('save', lang), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )),
                if (entryId != null) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: tr('remove_from_list', lang),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: saving ? null : () async {
                      final token = context.read<AuthService>().token;
                      final store = context.read<MediaListStore>();
                      final type = _data?['type'] as String? ?? 'ANIME';
                      final messenger = ScaffoldMessenger.of(context);
                      if (token == null || !await _confirmRemoval(ctx, lang)) return;
                      setModal(() { saving = true; errorText = null; });
                      final ok = await _service.deleteListEntry(entryId: entryId, token: token);
                      if (!ok) {
                        if (sheetContext.mounted) {
                          setModal(() { saving = false; errorText = tr('remove_failed', lang); });
                        }
                        return;
                      }
                      NotificationService().cancelForMedia(widget.animeId);
                      store.removeEntry(type, widget.animeId);
                      if (!mounted) return;
                      _load(force: true);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      messenger.showSnackBar(SnackBar(content: Text(tr('removed_from_list', lang))));
                    },
                  ),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmRemoval(BuildContext context, String lang) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('remove_from_list', lang)),
        content: Text(tr('remove_from_list_confirm', lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel', lang)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('remove', lang), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Widget _counterBtn(BuildContext context, IconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 18),
        ),
      );

  Widget _statusChip(BuildContext context, String label, String value, String selected, Function(String) onTap) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Chip(
        label: Text(label),
        backgroundColor: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
        labelStyle: TextStyle(color: isSelected ? Colors.white : null, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.tags
                .where((t) => _showAll || t['isMediaSpoiler'] != true || _showSpoilers)
                .take(_showAll ? 999 : 9)
                .map((t) => _tagChip(t['name'] as String, t['isMediaSpoiler'] == true))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _RelationsSection extends StatelessWidget {
  final List<Map<String, dynamic>> relations;
  final void Function(int id) onTap;
  const _RelationsSection({required this.relations, required this.onTap});

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

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: relations.length,
        itemBuilder: (_, i) {
          final node = relations[i]['node'] as Map<String, dynamic>? ?? {};
          final relType = _relationLabel(relations[i]['relationType'] as String? ?? '', lang);
          final relTitle = (node['title']?['english'] ?? node['title']?['romaji'] ?? '') as String;
          final relCover = node['coverImage']?['large'] as String?;
          final relId = node['id'] as int?;
          return GestureDetector(
            onTap: relId != null ? () => onTap(relId) : null,
            child: Container(
              width: 110,
              margin: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: relCover != null
                        ? CachedNetworkImage(imageUrl: relCover, width: 110, height: 150, fit: BoxFit.cover)
                        : Container(width: 110, height: 150,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest),
                  ),
                  const SizedBox(height: 4),
                  Text(relTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                  Text(relType, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          );
        },
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
          return GestureDetector(
            onTap: charId != null ? () => onTap(charId, name, img) : null,
            child: Container(
              width: 80,
              margin: const EdgeInsets.only(right: 10),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: img != null
                        ? CachedNetworkImage(imageUrl: img, width: 80, height: 110,
                            fit: BoxFit.cover, memCacheWidth: 160)
                        : Container(width: 80, height: 110,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest),
                  ),
                  const SizedBox(height: 4),
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
                  Text(role, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RecommendedSection extends StatelessWidget {
  final List<Map<String, dynamic>> recommendations;
  final void Function(int id) onTap;
  const _RecommendedSection({required this.recommendations, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 195,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: recommendations.length,
        itemBuilder: (_, i) {
          final rec = recommendations[i]['mediaRecommendation'] as Map<String, dynamic>?;
          if (rec == null) return const SizedBox.shrink();
          final recId = rec['id'] as int?;
          final recTitle = (rec['title']?['english'] ?? rec['title']?['romaji'] ?? '') as String;
          final recCover = rec['coverImage']?['large'] as String?;
          final rating = recommendations[i]['rating'] as int? ?? 0;
          return GestureDetector(
            onTap: recId != null ? () => onTap(recId) : null,
            child: Container(
              width: 110,
              margin: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: recCover != null
                        ? CachedNetworkImage(imageUrl: recCover, width: 110, height: 150, fit: BoxFit.cover)
                        : Container(width: 110, height: 150,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest),
                  ),
                  const SizedBox(height: 4),
                  Text(recTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                  Row(children: [
                    const Icon(Icons.thumb_up_outlined, size: 10, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text('$rating', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ]),
                ],
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
          GestureDetector(
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
              return GestureDetector(
                onTap: url != null ? () => onOpenUrl(url) : null,
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: thumb != null
                            ? CachedNetworkImage(imageUrl: thumb, width: 160, height: 110, fit: BoxFit.cover)
                            : Container(width: 160, height: 110,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest),
                      ),
                      const SizedBox(height: 4),
                      Text(epTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                    ],
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
