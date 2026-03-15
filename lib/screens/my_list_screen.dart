import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/anilist_service.dart';
import '../services/auth_service.dart';
import '../screens/detail_screen.dart';

class MyListScreen extends StatefulWidget {
  const MyListScreen({super.key});

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My List', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'ANIME'),
            Tab(text: 'MANGA'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MediaList(type: 'ANIME', isGridView: _isGridView),
          _MediaList(type: 'MANGA', isGridView: _isGridView),
        ],
      ),
    );
  }
}

class _MediaList extends StatefulWidget {
  final String type;
  final bool isGridView;
  const _MediaList({required this.type, required this.isGridView});

  @override
  State<_MediaList> createState() => _MediaListState();
}

class _MediaListState extends State<_MediaList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _service = AniListService();
  final _searchController = TextEditingController();
  Map<String, List<Map<String, dynamic>>> _lists = {};
  bool _loading = true;
  String? _error;
  bool _showSearch = false;
  String _searchQuery = '';
  final Set<String> _collapsedSections = {};

  final _statusOrder = [
    'CURRENT',
    'COMPLETED',
    'PAUSED',
    'DROPPED',
    'PLANNING',
    'REPEATING',
  ];

  final _animeStatusLabels = {
    'CURRENT': 'Watching',
    'COMPLETED': 'Completed',
    'PAUSED': 'On Hold',
    'DROPPED': 'Dropped',
    'PLANNING': 'Plan to Watch',
    'REPEATING': 'Rewatching',
  };

  final _mangaStatusLabels = {
    'CURRENT': 'Reading',
    'COMPLETED': 'Completed',
    'PAUSED': 'On Hold',
    'DROPPED': 'Dropped',
    'PLANNING': 'Plan to Read',
    'REPEATING': 'Rereading',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = 'Login to see your list';
      });
      return;
    }

    final userId = auth.user?['id'];
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'Could not get user ID';
      });
      return;
    }

    try {
      final raw = widget.type == 'ANIME'
          ? await _service.getUserAnimeList(userId, auth.token!)
          : await _service.getUserMangaList(userId, auth.token!);
      final typed = raw.map(
        (k, v) => MapEntry(k, v.cast<Map<String, dynamic>>()),
      );
      setState(() {
        _lists = typed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> _filterEntries(List<Map<String, dynamic>> entries) {
    if (_searchQuery.isEmpty) return entries;
    return entries.where((e) {
      final media = e['media'] as Map<String, dynamic>? ?? {};
      final title = (media['title']?['english'] ??
          media['title']?['romaji'] ??
          '') as String;
      return title.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.grey)),
            if (_error == 'Login to see your list')
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF02A9FF)),
                  onPressed: () async {
                    final auth = context.read<AuthService>();
                    try { await auth.login(); } catch (_) {}
                  },
                  child: const Text('Login with AniList',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
          ],
        ),
      );
    }
    if (_lists.isEmpty) {
      return const Center(child: Text('Nothing here yet'));
    }

    final labels = widget.type == 'ANIME' ? _animeStatusLabels : _mangaStatusLabels;

    return Column(
      children: [
        // In-list search bar
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _showSearch ? 56 : 0,
          child: _showSearch
              ? Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search in list...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          setState(() {
                            _showSearch = false;
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      ),
                      filled: true,
                      fillColor: const Color(0xFF21262D),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding:
                  EdgeInsets.only(top: _showSearch ? 0 : 8, bottom: 16),
              children: _statusOrder
                  .where((s) => (_lists[s]?.isNotEmpty ?? false))
                  .map((status) {
                final filtered = _filterEntries(_lists[status]!);
                if (filtered.isEmpty) return const SizedBox.shrink();
                return _buildSection(
                    status, labels[status] ?? status, filtered, widget.isGridView);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
      String statusKey, String title, List<Map<String, dynamic>> entries, bool isGrid) {
    final isCollapsed = _collapsedSections.contains(statusKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (isCollapsed) {
              _collapsedSections.remove(statusKey);
            } else {
              _collapsedSections.add(statusKey);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF02A9FF).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${entries.length}',
                      style: const TextStyle(
                          color: Color(0xFF02A9FF), fontSize: 12)),
                ),
                const Spacer(),
                Icon(
                  isCollapsed ? Icons.expand_more : Icons.expand_less,
                  color: Colors.grey,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (!isCollapsed) ...[
          if (isGrid)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.55,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: entries.length,
                itemBuilder: (_, i) =>
                    _GridCard(entry: entries[i], type: widget.type),
              ),
            )
          else
            ...entries.map((e) => _ListRow(entry: e, type: widget.type)),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

class _ListRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String type;
  const _ListRow({required this.entry, required this.type});

  @override
  Widget build(BuildContext context) {
    final media = entry['media'] as Map<String, dynamic>? ?? {};
    final progress = (entry['progress'] as num?)?.toInt() ?? 0;
    final score = (entry['score'] as num?)?.toDouble() ?? 0;
    final title = (media['title']?['english'] ??
        media['title']?['romaji'] ??
        'Unknown') as String;
    final image = media['coverImage']?['large'] as String?;
    final total = type == 'ANIME'
        ? media['episodes'] as int?
        : media['chapters'] as int?;
    final id = media['id'] as int?;

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: image != null
            ? CachedNetworkImage(
                imageUrl: image,
                width: 45,
                height: 64,
                fit: BoxFit.cover,
                memCacheWidth: 90,
                placeholder: (_, _) =>
                    Container(width: 45, height: 64, color: Colors.grey[800]),
                errorWidget: (_, _, _) =>
                    Container(width: 45, height: 64, color: Colors.grey[800]),
              )
            : Container(width: 45, height: 64, color: Colors.grey[800]),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Row(
        children: [
          Text(
            '$progress${total != null ? " / $total" : ""}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (score > 0) ...[
            const SizedBox(width: 10),
            const Icon(Icons.star, size: 12, color: Color(0xFFFFC107)),
            const SizedBox(width: 2),
            Text(
              score.toStringAsFixed(1),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
      onTap: id != null
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => DetailScreen(animeId: id)),
              )
          : null,
    );
  }
}

class _GridCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String type;
  const _GridCard({required this.entry, required this.type});

  @override
  Widget build(BuildContext context) {
    final media = entry['media'] as Map<String, dynamic>? ?? {};
    final title = (media['title']?['english'] ??
        media['title']?['romaji'] ??
        'Unknown') as String;
    final image = media['coverImage']?['large'] as String?;
    final id = media['id'] as int?;

    return GestureDetector(
      onTap: id != null
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => DetailScreen(animeId: id)),
              )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: image != null
                  ? CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      memCacheWidth: 200,
                      placeholder: (_, _) =>
                          Container(color: Colors.grey[800]),
                      errorWidget: (_, _, _) =>
                          Container(color: Colors.grey[800]),
                    )
                  : Container(color: Colors.grey[800]),
            ),
          ),
          const SizedBox(height: 4),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
