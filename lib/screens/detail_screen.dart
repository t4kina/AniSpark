import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/anilist_service.dart';
import '../services/auth_service.dart';
import '../providers/anime_list_provider.dart';
import '../models/anime.dart';
import '../utils/refresh_notifier.dart';
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
  bool _loading = true;
  bool _togglingFav = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final token = auth.isLoggedIn ? auth.token : null;
    final data = await _service.getAnimeDetail(widget.animeId, token);
    if (mounted) setState(() { if (data != null) _data = data; _loading = false; });
  }

  Future<void> _toggleFav() async {
    if (_togglingFav) return;
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    final wasFav = _data!['isFavourite'] == true;
    setState(() { _togglingFav = true; _data!['isFavourite'] = !wasFav; });
    final ok = await _service.toggleFavourite(animeId: widget.animeId, token: auth.token!);
    if (mounted) {
      setState(() {
        _togglingFav = false;
        if (!ok) _data!['isFavourite'] = wasFav; // revert on failure
      });
      if (ok) profileRefreshNotifier.value++;
    }
  }

  void _copyLink() {
    final type = (_data?['type'] as String? ?? 'ANIME').toLowerCase();
    final url = 'https://anilist.co/$type/${widget.animeId}';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Link copied to clipboard'),
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
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_data == null) return const Scaffold(body: Center(child: Text('Failed to load')));

    final provider = context.watch<AnimeListProvider>();
    final settings = context.read<SettingsProvider>();
    final d = _data!;

    final title = settings.resolveTitle(d['title'] as Map<String, dynamic>?);
    final cover = d['coverImage']?['extraLarge'] ?? d['coverImage']?['large'];
    final banner = d['bannerImage'] as String?;
    final score = d['averageScore'] as int?;
    final popularity = d['popularity'] as int?;
    final favourites = d['favourites'] as int?;
    final trending = d['trending'] as int?;
    final episodes = d['episodes'] as int?;
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
    final inList = listEntry != null || provider.isInList(widget.animeId);

    String listStatus = 'plan_to_watch';
    int listProgress = 0;
    double listScore = 0;
    if (listEntry != null) {
      listStatus = _fromAniListStatus(listEntry['status'] as String? ?? 'PLANNING');
      listProgress = (listEntry['progress'] as num?)?.toInt() ?? 0;
      listScore = (listEntry['score'] as num?)?.toDouble() ?? 0;
    } else if (provider.isInList(widget.animeId)) {
      final a = provider.getAnime(widget.animeId);
      if (a != null) {
        listStatus = a.status;
        listProgress = a.episodesWatched;
        listScore = (a.userScore ?? 0).toDouble();
      }
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
    final startStr = _dateStr(startDate);
    final endStr = _dateStr(endDate);
    final airingRange = [startStr, endStr].where((s) => s.isNotEmpty).join(' - ');

    final season = d['season'] as String?;
    final seasonYear = d['seasonYear'] as int?;
    final seasonStr = season != null && seasonYear != null
        ? '${_seasonLabel(season)} $seasonYear' : null;

    final totalDuration = (episodes != null && duration != null) ? episodes * duration : null;
    final watched = listProgress;
    final remaining = (episodes != null && duration != null)
        ? (episodes - watched) * duration : null;

    return Scaffold(
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
                                    'Episode ${nextAiring['episode']} airs en ${_airingCountdown(nextAiring['airingAt'] as int)}',
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
                                _statCell('AVERAGE SCORE',
                                    score != null ? '$score%' : '—',
                                    score != null && score >= 70 ? Colors.green : Colors.grey),
                                if (highestRated != null) ...[
                                  _vDivider(),
                                  _statCell('HIGHEST RATED', '#${highestRated['rank']}', null,
                                      sub: _rankingSub(highestRated)),
                                ],
                                if (mostPopular != null) ...[
                                  _vDivider(),
                                  _statCell('MOST POPULAR', '#${mostPopular['rank']}', null,
                                      sub: _rankingSub(mostPopular)),
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
                        inList ? _statusLabel(listStatus) : 'ADD TO LIST',
                        icon: inList ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                        sublabel: 'STATUS',
                        onTap: () => _showEditModal(context, provider, listStatus, listProgress, listScore),
                      ),
                      const SizedBox(width: 8),
                      _actionBtn(
                        context,
                        episodes != null
                            ? '$listProgress / $episodes EP'
                            : '$listProgress EP',
                        icon: Icons.play_circle_outline_rounded,
                        sublabel: 'PROGRESS',
                        onTap: () => _showEditModal(context, provider, listStatus, listProgress, listScore),
                      ),
                      const SizedBox(width: 8),
                      _actionBtn(
                        context,
                        listScore == 0 ? 'NOT SCORED' : listScore.toStringAsFixed(1),
                        icon: listScore == 0 ? Icons.star_outline_rounded : Icons.star_rounded,
                        sublabel: 'SCORE',
                        onTap: () => _showEditModal(context, provider, listStatus, listProgress, listScore),
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
                    _sectionTitle('SERIES INFO'),
                    const SizedBox(height: 12),
                    _infoGrid([
                      if (format != null) _InfoItem('TYPE', _formatLabel(format)),
                      if (airingRange.isNotEmpty) _InfoItem('AIRING', airingRange),
                      if (episodes != null) _InfoItem('EPISODES', '$episodes'),
                      if (duration != null) _InfoItem('RUNTIME', '${_durationStr(duration, settings.language)} per episode'),
                      if (totalDuration != null) _InfoItem('ESTIMATED TOTAL DURATION', _durationStr(totalDuration, settings.language)),
                      if (remaining != null && remaining > 0) _InfoItem('TIME REMAINING TO FINISH', _durationStr(remaining, settings.language)),
                      if (seasonStr != null) _InfoItem('SEASON', seasonStr),
                      if (popularity != null) _InfoItem('POPULARITY', 'On ${_fmt(popularity)} user\'s lists'),
                      if (favourites != null) _InfoItem('FAVORITES', _fmt(favourites)),
                      if (trending != null) _InfoItem('TRENDING', '$trending recent user list updates'),
                    ]),
                  ],
                )),

                // ── Titles ──
                _sectionPad(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('TITLES'),
                    const SizedBox(height: 10),
                    if (d['title']?['romaji'] != null) _titleRow('ROMAJI', d['title']['romaji'] as String),
                    if (d['title']?['english'] != null) _titleRow('ENGLISH', d['title']['english'] as String),
                    if (d['title']?['native'] != null) _titleRow('NATIVE', d['title']['native'] as String),
                    if (synonyms.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _titleRow('OTHER NAMES', synonyms.join('\n')),
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
                      _sectionTitle('GENRES'),
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
                      _sectionTitle('PRODUCERS'),
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
                  _sectionPad(_sectionTitle('RELATIONS')),
                  _RelationsSection(
                    relations: relations,
                    onTap: (id) => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => DetailScreen(animeId: id))),
                  ),
                  const Divider(height: 1),
                ],

                // ── Characters ──
                if (characters.isNotEmpty) ...[
                  _sectionPad(_sectionTitle('CHARACTERS')),
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
                  _sectionPad(_sectionTitle('RECOMMENDED')),
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

          // ── Overlay buttons ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _overlayBtn(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                _overlayBtn(
                  icon: Icons.ios_share_rounded,
                  onPressed: _copyLink,
                ),
                const SizedBox(width: 8),
                _overlayBtn(
                  icon: d['isFavourite'] == true ? Icons.favorite : Icons.favorite_border,
                  color: d['isFavourite'] == true ? Colors.red : Colors.white,
                  onPressed: _toggleFav,
                ),
                const SizedBox(width: 8),
                _overlayBtn(
                  icon: Icons.more_horiz,
                  onPressed: () => _showEditModal(context, provider, listStatus, listProgress, listScore),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static Widget _overlayBtn({
    required IconData icon,
    Color color = Colors.white,
    required VoidCallback onPressed,
  }) =>
      GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      );

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

  String _airingCountdown(int airingAt) {
    final diff = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000).difference(DateTime.now());
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
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

  String _dateStr(Map<String, dynamic>? d) {
    if (d == null) return '';
    final y = d['year']; final m = d['month']; final day = d['day'];
    if (y == null) return '';
    if (m == null) return '$y';
    final months = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
    final mStr = (m as int) >= 1 && m <= 12 ? months[m - 1] : '$m';
    if (day == null) return '$mStr $y';
    return '$day $mStr $y';
  }

  String _formatLabel(String f) => switch (f) {
    'TV' => 'TV', 'MOVIE' => 'Movie', 'OVA' => 'OVA',
    'ONA' => 'ONA', 'SPECIAL' => 'Special', 'MUSIC' => 'Music',
    'TV_SHORT' => 'TV Short', _ => f,
  };

  String _statusLabel(String s) {
    final manga = (_data?['type'] as String?) == 'MANGA';
    return switch (s) {
      'watching'      => manga ? 'READING' : 'WATCHING',
      'completed'     => 'COMPLETED',
      'plan_to_watch' => manga ? 'PLAN TO READ' : 'PLAN TO WATCH',
      'dropped'       => 'DROPPED',
      'on_hold'       => 'ON HOLD',
      'rewatching'    => manga ? 'REREADING' : 'REWATCHING',
      _               => s.toUpperCase(),
    };
  }

  String _seasonLabel(String s) => switch (s) {
    'WINTER' => 'Winter', 'SPRING' => 'Spring',
    'SUMMER' => 'Summer', 'FALL' => 'Fall', _ => s,
  };

  String _rankingSub(Map<String, dynamic>? r) {
    if (r == null) return 'All Time';
    if (r['allTime'] == true) return 'All Time';
    final season = r['season'] as String?;
    final year = r['year'];
    if (season != null && year != null) return '${_seasonLabel(season)} $year';
    if (year != null) return '$year';
    return 'All Time';
  }

  void _openCover(BuildContext context, String imageUrl) {
    Navigator.push(context, PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, _, _) => _CoverViewer(tag: 'cover_${widget.animeId}', imageUrl: imageUrl),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ));
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showEditModal(BuildContext context, AnimeListProvider provider,
      String initialStatus, int initialProgress, double initialScore) {
    final anime = Anime.fromApi(_data!);
    final resolvedTitle = context.read<SettingsProvider>().resolveTitle(_data!['title'] as Map<String, dynamic>?);
    final totalEps = (_data!['episodes'] ?? _data!['chapters']) as int?;
    final isManga = (_data!['type'] as String?) == 'MANGA';

    String selectedStatus = initialStatus;
    int progress = initialProgress;
    double score = initialScore;

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
              const Text('Status', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _statusChip(ctx, isManga ? 'Reading' : 'Watching', 'watching', selectedStatus, (v) => setModal(() => selectedStatus = v)),
                _statusChip(ctx, 'Completed', 'completed', selectedStatus, (v) => setModal(() => selectedStatus = v)),
                _statusChip(ctx, isManga ? 'Plan to Read' : 'Plan to Watch', 'plan_to_watch', selectedStatus, (v) => setModal(() => selectedStatus = v)),
                _statusChip(ctx, 'On Hold', 'on_hold', selectedStatus, (v) => setModal(() => selectedStatus = v)),
                _statusChip(ctx, 'Dropped', 'dropped', selectedStatus, (v) => setModal(() => selectedStatus = v)),
                _statusChip(ctx, isManga ? 'Rereading' : 'Rewatching', 'rewatching', selectedStatus, (v) => setModal(() => selectedStatus = v)),
              ]),
              const SizedBox(height: 16),
              const Text('Progress', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: [
                _counterBtn(ctx, Icons.remove, () { if (progress > 0) setModal(() => progress--); }),
                const SizedBox(width: 12),
                Expanded(child: Text(totalEps != null ? '$progress / $totalEps ep' : '$progress ep',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                const SizedBox(width: 12),
                _counterBtn(ctx, Icons.add, () { if (totalEps == null || progress < totalEps) setModal(() => progress++); }),
              ]),
              const SizedBox(height: 16),
              const Text('Score (0–10)', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: [
                _counterBtn(ctx, Icons.remove, () { if (score > 0) setModal(() => score = (score - 0.5).clamp(0, 10)); }),
                const SizedBox(width: 12),
                Expanded(child: Text(score == 0 ? '—' : score.toStringAsFixed(1),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                const SizedBox(width: 12),
                _counterBtn(ctx, Icons.add, () { if (score < 10) setModal(() => score = (score + 0.5).clamp(0, 10)); }),
              ]),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF02A9FF),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    anime.status = selectedStatus;
                    anime.episodesWatched = progress;
                    anime.userScore = score.round();
                    provider.addAnime(anime);
                    final auth = context.read<AuthService>();
                    if (auth.isLoggedIn) {
                      await _service.saveListEntry(
                          mediaId: anime.id, status: _toAniListStatus(selectedStatus),
                          progress: progress, score: score, token: auth.token!);
                      _load();
                      listRefreshNotifier.value++;
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${anime.title} saved!')));
                  },
                  child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )),
                if (provider.isInList(widget.animeId)) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () { provider.removeAnime(widget.animeId); Navigator.pop(context); },
                  ),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
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
        backgroundColor: isSelected ? const Color(0xFF02A9FF) : Theme.of(context).colorScheme.surfaceContainerHighest,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SUMMARY',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
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
              child: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Read more',
                    style: TextStyle(color: Color(0xFF02A9FF), fontSize: 12)),
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
    final spoilerCount = widget.tags.where((t) => t['isMediaSpoiler'] == true).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('TAGS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: Colors.grey, letterSpacing: 0.5)),
              ),
              if (spoilerCount > 0)
                _smallBtn(
                  _showSpoilers ? 'Hide Spoiler Tag' : 'Show $spoilerCount Spoiler Tag',
                  () => setState(() => _showSpoilers = !_showSpoilers),
                ),
              const SizedBox(width: 8),
              _smallBtn(
                _showAll ? 'Show Less' : 'Show All ${widget.tags.length} Tags',
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

  String _relationLabel(String s) => switch (s) {
    'PREQUEL' => 'Prequel', 'SEQUEL' => 'Sequel', 'SIDE_STORY' => 'Side Story',
    'PARENT' => 'Parent', 'ALTERNATIVE' => 'Alternative', 'SUMMARY' => 'Summary',
    'SPIN_OFF' => 'Spin Off', 'ADAPTATION' => 'Adaptation', 'SOURCE' => 'Source',
    'CHARACTER' => 'Character', _ => s,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: relations.length,
        itemBuilder: (_, i) {
          final node = relations[i]['node'] as Map<String, dynamic>? ?? {};
          final relType = _relationLabel(relations[i]['relationType'] as String? ?? '');
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

  @override
  Widget build(BuildContext context) {
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
          final role = (edge['role'] as String? ?? '').toLowerCase();
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TRAILER',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
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
    final site = episodes.isNotEmpty ? episodes.first['site'] as String? : null;
    final title = site != null
        ? 'EPISODES (AVAILABLE ON ${site.toUpperCase()})'
        : 'EPISODES';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('EXTERNAL AND STREAMING LINKS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
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
