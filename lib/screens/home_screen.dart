import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../services/anilist_service.dart';
import '../services/auth_service.dart';
import '../providers/settings_provider.dart';
import '../widgets/anime_card.dart';
import 'detail_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = AniListService();
  List<dynamic> _trending = [];
  List<dynamic> _seasonal = [];
  List<dynamic> _popular = [];
  List<dynamic> _topAiring = [];
  List<dynamic> _trendingManga = [];
  List<dynamic> _topManga = [];
  List<dynamic> _manhwa = [];
  List<dynamic> _weeklySchedule = [];
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCalendar());
  }

  Future<void> _loadCalendar() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn || auth.token == null) return;
    final schedule = await _service.getWeeklySchedule(auth.token!);
    if (mounted) setState(() => _weeklySchedule = schedule);
  }

  Future<List<dynamic>> _safe(Future<List<dynamic>> f) =>
      f.catchError((_) => <dynamic>[]);

  Future<void> _load() async {
    setState(() { _loading = true; _hasError = false; });
    try {
      final results = await Future.wait([
        _safe(_service.getTrending()),
        _safe(_service.getThisSeason()),
        _safe(_service.getNextSeason()),
        _safe(_service.getTopAiring()),
        _safe(_service.getTrendingManga()),
        _safe(_service.getTopManga()),
        _safe(_service.getManhwa()),
      ]);
      final allEmpty = results.every((r) => r.isEmpty);
      setState(() {
        _trending = results[0];
        _seasonal = results[1];
        _popular = results[2];
        _topAiring = results[3];
        _trendingManga = results[4];
        _topManga = results[5];
        _manhwa = results[6];
        _loading = false;
        _hasError = allEmpty;
      });
    } catch (_) {
      setState(() { _loading = false; _hasError = true; });
    }
  }

  String get _currentSeasonLabel {
    final month = DateTime.now().month;
    final year = DateTime.now().year;
    String season;
    if (month >= 1 && month <= 3) { season = 'WINTER'; }
    else if (month >= 4 && month <= 6) { season = 'SPRING'; }
    else if (month >= 7 && month <= 9) { season = 'SUMMER'; }
    else { season = 'FALL'; }
    return '$season $year';
  }

  String get _nextSeasonLabel {
    final month = DateTime.now().month;
    final year = DateTime.now().year;
    if (month >= 10) return 'WINTER ${year + 1}';
    if (month >= 7) return 'FALL $year';
    if (month >= 4) return 'SUMMER $year';
    return 'SPRING $year';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Discover',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
              child: AbsorbPointer(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon:
                        Icon(Icons.search, size: 20, color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? _buildShimmer()
                : _hasError
                    ? _buildError()
                    : RefreshIndicator(
                    onRefresh: _load,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_weeklySchedule.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _sectionHeader('THIS WEEK'),
                            const SizedBox(height: 10),
                            _buildWeeklySchedule(),
                            const SizedBox(height: 8),
                            const Divider(indent: 16, endIndent: 16),
                          ],
                          const SizedBox(height: 12),
                          _sectionHeader('CURRENTLY TRENDING ANIME', items: _trending),
                          const SizedBox(height: 10),
                          _buildHorizontalRow(_trending),
                          const SizedBox(height: 20),
                          _sectionHeader('CURRENT SEASON - $_currentSeasonLabel', items: _seasonal),
                          const SizedBox(height: 10),
                          _buildHorizontalRow(_seasonal),
                          const SizedBox(height: 20),
                          _sectionHeader('UPCOMING SEASON - $_nextSeasonLabel', items: _popular),
                          const SizedBox(height: 10),
                          _buildHorizontalRow(_popular),
                          const SizedBox(height: 20),
                          _sectionHeader('TOP AIRING', items: _topAiring),
                          const SizedBox(height: 10),
                          _buildHorizontalRow(_topAiring),
                          const SizedBox(height: 28),
                          const Divider(indent: 16, endIndent: 16),
                          const SizedBox(height: 16),
                          _sectionHeader('TRENDING MANGA', items: _trendingManga),
                          const SizedBox(height: 10),
                          _buildHorizontalRow(_trendingManga),
                          const SizedBox(height: 20),
                          _sectionHeader('TOP MANGA ALL TIME', items: _topManga),
                          const SizedBox(height: 10),
                          _buildHorizontalRow(_topManga),
                          const SizedBox(height: 20),
                          _sectionHeader('POPULAR MANHWA', items: _manhwa),
                          const SizedBox(height: 10),
                          _buildHorizontalRow(_manhwa),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {List<dynamic>? items}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (items != null && items.isNotEmpty)
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _BrowseAllScreen(title: title, items: items),
                  ),
                ),
                child: Builder(builder: (ctx) => Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                )),
              ),
          ],
        ),
      );

  Widget _buildHorizontalRow(List<dynamic> items) => SizedBox(
        height: 222,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          itemCount: items.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 120,
              child: AnimeCard(animeData: items[i]),
            ),
          ),
        ),
      );

  Widget _buildWeeklySchedule() {
    final settings = context.read<SettingsProvider>();
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 16, right: 8),
        itemCount: _weeklySchedule.length,
        itemBuilder: (ctx, i) {
          final item = _weeklySchedule[i];
          final media = item['media'] as Map<String, dynamic>? ?? {};
          final id = media['id'] as int?;
          final cover = media['coverImage']?['large'] as String?;
          final title = settings.resolveTitle(media['title'] as Map<String, dynamic>?);
          final airingAt = (item['airingAt'] as num?)?.toInt() ?? 0;
          final episode = (item['episode'] as num?)?.toInt() ?? 0;
          final dt = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);
          final dayLabel = days[dt.weekday - 1];
          final timeLabel = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

          return GestureDetector(
            onTap: id != null
                ? () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => DetailScreen(animeId: id)))
                : null,
            child: Container(
              width: 220,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                    child: cover != null
                        ? CachedNetworkImage(
                            imageUrl: cover,
                            width: 70,
                            height: 130,
                            fit: BoxFit.cover,
                            memCacheWidth: 140,
                          )
                        : Container(width: 70, color: Theme.of(ctx).colorScheme.surfaceContainerHighest),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Builder(builder: (c) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(c).colorScheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$dayLabel  $timeLabel',
                              style: TextStyle(fontSize: 10, color: Theme.of(c).colorScheme.primary, fontWeight: FontWeight.w600),
                            ),
                          )),
                          const SizedBox(height: 6),
                          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Episode $episode', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No se pudo cargar el contenido',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );

  Widget _buildShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
        baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDark ? Colors.grey[600]! : Colors.grey[100]!,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(7, (_) => _shimmerSection()),
          ),
        ),
      );
  }

  Widget _shimmerSection() => Column(

        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Container(
              width: 120,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          SizedBox(
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 6,
              itemBuilder: (_, _) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 170,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 100,
                      height: 12,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}

// ── Browse All Screen ────────────────────────────────────────────────────────

class _BrowseAllScreen extends StatelessWidget {
  final String title;
  final List<dynamic> items;

  const _BrowseAllScreen({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.53,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i] as Map<String, dynamic>;
          final id = item['id'] as int?;
          final cover = item['coverImage']?['large'] as String?;
          final title = (item['title']?['english'] ?? item['title']?['romaji'] ?? '') as String;
          final score = item['averageScore'] as int?;
          final cs = Theme.of(context).colorScheme;

          return GestureDetector(
            onTap: id != null
                ? () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => DetailScreen(animeId: id)))
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        cover != null
                            ? CachedNetworkImage(
                                imageUrl: cover,
                                fit: BoxFit.cover,
                                memCacheWidth: 200,
                                placeholder: (_, _) => Container(
                                    color: cs.surfaceContainerHighest),
                                errorWidget: (context, error, stack) => Container(
                                    color: cs.surfaceContainerHighest),
                              )
                            : Container(color: cs.surfaceContainerHighest),
                        if (score != null)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 4, horizontal: 6),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.75),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: Text(
                                '★ ${(score / 10).toStringAsFixed(1)}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
