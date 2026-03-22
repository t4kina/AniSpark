import 'dart:async';
import 'package:flutter/material.dart';
import '../services/anilist_service.dart';
import '../widgets/anime_card.dart';

class _SearchFilters {
  String? genre;
  String? format;
  String? status;
  String? sort;
  int? year;

  bool get hasFilters =>
      genre != null || format != null || status != null ||
      sort != null || year != null;

  void clear() {
    genre = null;
    format = null;
    status = null;
    sort = null;
    year = null;
  }

  _SearchFilters copy() => _SearchFilters()
    ..genre = genre
    ..format = format
    ..status = status
    ..sort = sort
    ..year = year;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with TickerProviderStateMixin {
  final _service = AniListService();
  final _controller = TextEditingController();
  late final TabController _tabController;
  Timer? _debounce;

  List<dynamic> _animeResults = [];
  List<dynamic> _mangaResults = [];
  bool _loading = false;
  bool _searched = false;
  final _filters = _SearchFilters();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          final q = _controller.text.trim();
          if (q.isNotEmpty) _search(q);
        }
      });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _animeResults = [];
        _mangaResults = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _loading = true);
    if (_tabController.index == 0) {
      final r = await _service.searchAnime(
        query,
        genre: _filters.genre,
        format: _filters.format,
        status: _filters.status,
        sort: _filters.sort,
        year: _filters.year,
      );
      if (mounted) setState(() { _animeResults = r; _loading = false; _searched = true; });
    } else {
      final r = await _service.searchManga(
        query,
        genre: _filters.genre,
        format: _filters.format,
        status: _filters.status,
        sort: _filters.sort,
        year: _filters.year,
      );
      if (mounted) setState(() { _mangaResults = r; _loading = false; _searched = true; });
    }
  }

  void _showFilters() {
    final draft = _filters.copy();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FilterSheet(
        isAnime: _tabController.index == 0,
        filters: draft,
        onApply: (f) {
          setState(() {
            _filters.genre = f.genre;
            _filters.format = f.format;
            _filters.status = f.status;
            _filters.sort = f.sort;
            _filters.year = f.year;
          });
          final q = _controller.text.trim();
          if (q.isNotEmpty) _search(q);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: false,
          decoration: InputDecoration(
            hintText: 'Search anime or manga...',
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      setState(() {
                        _animeResults = [];
                        _mangaResults = [];
                        _searched = false;
                      });
                    },
                  )
                : null,
          ),
          onChanged: _onQueryChanged,
          onSubmitted: _search,
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.tune,
              color: _filters.hasFilters
                  ? const Color(0xFF02A9FF)
                  : Colors.grey,
            ),
            onPressed: _showFilters,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'ANIME'), Tab(text: 'MANGA')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _ResultsGrid(
                  results: _animeResults,
                  searched: _searched,
                ),
                _ResultsGrid(
                  results: _mangaResults,
                  searched: _searched,
                ),
              ],
            ),
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  final List<dynamic> results;
  final bool searched;
  const _ResultsGrid({required this.results, required this.searched});

  @override
  Widget build(BuildContext context) {
    if (!searched) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('Search for anime or manga',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    if (results.isEmpty) {
      return const Center(child: Text('No results found'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: results.length,
      itemBuilder: (_, i) => AnimeCard(animeData: results[i]),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final bool isAnime;
  final _SearchFilters filters;
  final void Function(_SearchFilters) onApply;

  const _FilterSheet({
    required this.isAnime,
    required this.filters,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final _SearchFilters _draft;

  static const _genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy',
    'Horror', 'Mecha', 'Mystery', 'Psychological', 'Romance',
    'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural', 'Thriller',
  ];
  static const _animeFormats = ['TV', 'MOVIE', 'OVA', 'ONA', 'SPECIAL', 'MUSIC'];
  static const _mangaFormats = ['MANGA', 'NOVEL', 'ONE_SHOT'];
  static const _statuses = ['FINISHED', 'RELEASING', 'NOT_YET_RELEASED', 'CANCELLED'];
  static const _sorts = [
    ('Popularity', 'POPULARITY_DESC'),
    ('Score', 'SCORE_DESC'),
    ('Trending', 'TRENDING_DESC'),
    ('Newest', 'START_DATE_DESC'),
  ];

  @override
  void initState() {
    super.initState();
    _draft = widget.filters.copy();
  }

  @override
  Widget build(BuildContext context) {
    final formats = widget.isAnime ? _animeFormats : _mangaFormats;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text('Filters',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _label('Genre'),
          _chipWrap(_genres, _draft.genre,
              (v) => setState(() => _draft.genre = v == _draft.genre ? null : v)),
          const SizedBox(height: 12),
          _label('Format'),
          _chipWrap(formats, _draft.format,
              (v) => setState(() => _draft.format = v == _draft.format ? null : v)),
          const SizedBox(height: 12),
          _label('Status'),
          _chipWrap(_statuses, _draft.status,
              (v) => setState(() => _draft.status = v == _draft.status ? null : v)),
          const SizedBox(height: 12),
          _label('Sort By'),
          _chipWrap(
            _sorts.map((e) => e.$1).toList(),
            _sorts.firstWhere((e) => e.$2 == _draft.sort, orElse: () => ('', '')).$1,
            (label) {
              final match = _sorts.firstWhere((e) => e.$1 == label, orElse: () => ('', ''));
              setState(() => _draft.sort = match.$2.isEmpty ? null :
                  (_draft.sort == match.$2 ? null : match.$2));
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    side: const BorderSide(color: Colors.grey),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    _draft.clear();
                    setState(() {});
                  },
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF02A9FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onApply(_draft);
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
      );

  Widget _chipWrap(
    List<String> options,
    String? selected,
    void Function(String) onTap,
  ) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.map((opt) {
          final isSelected = opt == selected;
          return GestureDetector(
            onTap: () => onTap(opt),
            child: Chip(
              label: Text(opt,
                  style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? Colors.white : null)),
              backgroundColor:
                  isSelected ? const Color(0xFF02A9FF) : Theme.of(context).colorScheme.surfaceContainerHighest,
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            ),
          );
        }).toList(),
      );
}
