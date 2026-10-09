import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:confetti/confetti.dart';
import '../providers/media_list_store.dart';
import '../services/auth_service.dart';
import '../screens/detail_screen.dart';
import '../main.dart';
import '../providers/settings_provider.dart';
import '../utils/translations.dart' show tr;
import '../utils/refresh_notifier.dart';
import '../utils/score_utils.dart';
import '../services/notification_service.dart';

enum _SortMode { lastUpdated, alphabetical, ratingHigh, ratingLow }

// ─── Standalone Anime List Screen ──────────────────────────────────────────

class AnimeListScreen extends StatelessWidget {
  const AnimeListScreen({super.key});

  @override
  Widget build(BuildContext context) => _ListTabScreen(type: 'ANIME');
}

// ─── Standalone Manga List Screen ──────────────────────────────────────────

class MangaListScreen extends StatelessWidget {
  const MangaListScreen({super.key});

  @override
  Widget build(BuildContext context) => _ListTabScreen(type: 'MANGA');
}

// ─── Shared wrapper screen ─────────────────────────────────────────────────

class _ListTabScreen extends StatefulWidget {
  final String type;
  const _ListTabScreen({required this.type});

  @override
  State<_ListTabScreen> createState() => _ListTabScreenState();
}

class _ListTabScreenState extends State<_ListTabScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.lastUpdated;
  Set<String> _activeGenres = {};

  static const _genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy', 'Horror',
    'Mahou Shoujo', 'Mecha', 'Music', 'Mystery', 'Psychological', 'Romance',
    'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural', 'Thriller',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showGenreFilter(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Filter by Genre',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  const Spacer(),
                  if (_activeGenres.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(() => _activeGenres = {});
                        setSheet(() {});
                      },
                      child: const Text('Clear', style: TextStyle(fontSize: 13)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _genres.map((g) {
                  final selected = _activeGenres.contains(g);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _activeGenres.remove(g);
                        } else {
                          _activeGenres.add(g);
                        }
                      });
                      setSheet(() {});
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? cs.primary : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? cs.primary : cs.outline.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        g,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          color: selected ? Colors.white : cs.onSurface,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final avatar = auth.user?['avatar']?['large'] as String?;
    final title = widget.type == 'ANIME' ? tr('nav_anime', lang) : tr('nav_manga', lang);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: GestureDetector(
          onTap: () => MainNavigation.navigateToTab(4),
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: ClipOval(
                  child: avatar != null
                      ? CachedNetworkImage(
                          imageUrl: avatar,
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          memCacheWidth: 64,
                        )
                      : Container(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person, size: 16, color: Colors.grey),
                        ),
                ),
              ),
            ),
          ),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: Icon(
              Icons.tune_rounded,
              size: 22,
              color: _activeGenres.isNotEmpty ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
            onPressed: () => _showGenreFilter(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: PopupMenuButton<_SortMode>(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.swap_vert, color: Colors.grey, size: 22),
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (_) => [
              _sortItem(_SortMode.lastUpdated, tr('last_updated', lang), Icons.history),
              _sortItem(_SortMode.alphabetical, tr('alphabetical', lang), Icons.sort_by_alpha),
              _sortItem(_SortMode.ratingHigh, tr('rating_high', lang), Icons.star),
              _sortItem(_SortMode.ratingLow, tr('rating_low', lang), Icons.star_outline),
            ],
          ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: tr('filter_by_name', lang),
                prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        }),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: _MediaList(
              type: widget.type,
              searchQuery: _searchQuery,
              sortMode: _sortMode,
              activeGenres: _activeGenres,
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_SortMode> _sortItem(_SortMode mode, String label, IconData icon) =>
      PopupMenuItem(
        value: mode,
        child: Row(
          children: [
            Icon(icon, size: 16,
                color: _sortMode == mode ? Theme.of(context).colorScheme.primary : Colors.grey),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: _sortMode == mode ? Theme.of(context).colorScheme.primary : null,
                    fontSize: 13)),
          ],
        ),
      );
}

// ─── Media List (content) ──────────────────────────────────────────────────

class _MediaList extends StatefulWidget {
  final String type;
  final String searchQuery;
  final _SortMode sortMode;
  final Set<String> activeGenres;
  const _MediaList({required this.type, this.searchQuery = '', this.sortMode = _SortMode.lastUpdated, this.activeGenres = const {}});

  @override
  State<_MediaList> createState() => _MediaListState();
}

class _MediaListState extends State<_MediaList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final Set<String> _collapsedSections = {};

  final _statusOrder = [
    'CURRENT',
    'COMPLETED',
    'PAUSED',
    'DROPPED',
    'PLANNING',
    'REPEATING',
  ];

  Map<String, String> _animeStatusLabels(String lang) => {
    'CURRENT': tr('watching', lang),
    'COMPLETED': tr('completed', lang),
    'PAUSED': tr('on_hold', lang),
    'DROPPED': tr('dropped', lang),
    'PLANNING': tr('plan_to_watch', lang),
    'REPEATING': tr('rewatching', lang),
  };

  Map<String, String> _mangaStatusLabels(String lang) => {
    'CURRENT': tr('reading', lang),
    'COMPLETED': tr('completed', lang),
    'PAUSED': tr('on_hold', lang),
    'DROPPED': tr('dropped', lang),
    'PLANNING': tr('plan_to_read', lang),
    'REPEATING': tr('rereading', lang),
  };

  AuthService? _auth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _auth = context.read<AuthService>()..addListener(_onAuthChanged);
      _load();
    });
    listRefreshNotifier.addListener(_onRefreshRequested);
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    listRefreshNotifier.removeListener(_onRefreshRequested);
    super.dispose();
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || !mounted || !auth.isLoggedIn) return;
    if (context.read<MediaListStore>().listsOf(widget.type) == null) _load();
  }

  void _onRefreshRequested() => _load(force: true);

  /// Shows the cached list instantly and refreshes it from AniList, then
  /// reschedules episode notifications whenever a fresh anime list arrives.
  Future<void> _load({bool force = false}) async {
    final auth = context.read<AuthService>();
    final userId = auth.user?['id'] as int?;
    final token = auth.token;
    if (userId == null || token == null) return;
    final store = context.read<MediaListStore>();
    final settings = context.read<SettingsProvider>();
    final gotFresh = await store.load(
      widget.type,
      userId: userId,
      token: token,
      force: force,
    );
    final lists = store.listsOf(widget.type);
    if (gotFresh && widget.type == 'ANIME' && lists != null) {
      NotificationService().scheduleForAnimeList(lists, settings);
    }
  }

  Future<void> _refresh() async {
    await _load(force: true);
    if (!mounted) return;
    if (context.read<MediaListStore>().errorOf(widget.type) != null) {
      _showSnack(tr('load_error', context.read<SettingsProvider>().language));
    }
  }

  void _showSnack(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 3),
        action: action,
      ));
  }

  /// Adds [delta] to an entry's progress. The row updates instantly; the last
  /// episode opens the completion dialog instead, and a failed save is
  /// reverted with a message.
  Future<void> _changeProgress(Map<String, dynamic> entry, int delta) async {
    final token = context.read<AuthService>().token;
    final store = context.read<MediaListStore>();
    final settings = context.read<SettingsProvider>();
    final media = entry['media'] as Map<String, dynamic>? ?? {};
    final mediaId = media['id'] as int?;
    if (token == null || mediaId == null || store.isSaving(mediaId)) return;

    final progress = (entry['progress'] as num?)?.toInt() ?? 0;
    final total = widget.type == 'ANIME'
        ? media['episodes'] as int?
        : media['chapters'] as int?;
    final newProgress = progress + delta;
    if (newProgress < 0 || (total != null && newProgress > total)) return;
    HapticFeedback.selectionClick();

    // For the last episode, show the completion dialog BEFORE saving.
    // If the user dismisses it, nothing is written to AniList.
    if (delta > 0 && total != null && newProgress == total) {
      await _showCompletionDialog(entry, mediaId, total);
      return;
    }

    final ok = await store.setProgress(widget.type, mediaId, newProgress, token: token);
    if (!mounted) return;
    final lang = settings.language;
    if (!ok) {
      _showSnack(tr('save_failed', lang));
      return;
    }
    final title = settings.resolveTitle(media['title'] as Map<String, dynamic>?);
    final unit = widget.type == 'ANIME' ? tr('episode', lang) : tr('chapter', lang);
    _showSnack(
      '$title · $unit $newProgress',
      action: SnackBarAction(
        label: tr('undo', lang),
        onPressed: () => _undoProgress(mediaId, progress),
      ),
    );
  }

  Future<void> _undoProgress(int mediaId, int previousProgress) async {
    if (!mounted) return;
    final token = context.read<AuthService>().token;
    final store = context.read<MediaListStore>();
    final lang = context.read<SettingsProvider>().language;
    if (token == null) return;
    final ok = await store.setProgress(widget.type, mediaId, previousProgress, token: token);
    if (!ok && mounted) _showSnack(tr('save_failed', lang));
  }

  Future<void> _showCompletionDialog(
    Map<String, dynamic> entry,
    int mediaId,
    int total,
  ) async {
    final settings = context.read<SettingsProvider>();
    final store = context.read<MediaListStore>();
    final media = entry['media'] as Map<String, dynamic>? ?? {};
    final title = settings.resolveTitle(media['title'] as Map<String, dynamic>?);
    final coverImage = media['coverImage']?['large'] as String?;
    final averageScore = (media['averageScore'] as num?)?.toDouble();
    final initialScore = (entry['score'] as num?)?.toDouble() ?? 0;

    if (!mounted) return;
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (ctx, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
      pageBuilder: (ctx, _, _) => _CompletionDialog(
        title: title,
        coverImage: coverImage,
        averageScore: averageScore,
        initialScore: initialScore,
        type: widget.type,
        onComplete: (score) async {
          final token = context.read<AuthService>().token;
          if (token == null || !mounted) return false;
          return store.saveFields(
            widget.type,
            mediaId,
            status: 'COMPLETED',
            progress: total,
            // Only write the score when the user changed it, so AniList keeps
            // the exact value in the user's own score format otherwise.
            scoreRaw: score != initialScore ? toRawScore(score) : null,
            token: token,
          );
        },
      ),
    );
  }


  List<Map<String, dynamic>> _filterEntries(
      List<Map<String, dynamic>> entries) {
    var result = entries.where((e) {
      final media = e['media'] as Map<String, dynamic>? ?? {};
      if (widget.searchQuery.isNotEmpty) {
        final title = (media['title']?['english'] ??
            media['title']?['romaji'] ??
            '') as String;
        if (!title.toLowerCase().contains(widget.searchQuery.toLowerCase())) return false;
      }
      if (widget.activeGenres.isNotEmpty) {
        final genres = (media['genres'] as List<dynamic>? ?? []).cast<String>();
        if (!widget.activeGenres.any((g) => genres.contains(g))) return false;
      }
      return true;
    }).toList();

    switch (widget.sortMode) {
      case _SortMode.alphabetical:
        result.sort((a, b) {
          final ta = ((a['media']?['title']?['english'] ?? a['media']?['title']?['romaji'] ?? '') as String).toLowerCase();
          final tb = ((b['media']?['title']?['english'] ?? b['media']?['title']?['romaji'] ?? '') as String).toLowerCase();
          return ta.compareTo(tb);
        });
      case _SortMode.ratingHigh:
        result.sort((a, b) => ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0));
      case _SortMode.ratingLow:
        result.sort((a, b) => ((a['score'] as num?) ?? 0).compareTo((b['score'] as num?) ?? 0));
      case _SortMode.lastUpdated:
        break;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLoggedIn = context.select<AuthService, bool>((auth) => auth.isLoggedIn);
    final (lists, loading, error) = context.select<MediaListStore, (MediaLists?, bool, Object?)>(
        (store) => (store.listsOf(widget.type), store.isLoading(widget.type), store.errorOf(widget.type)));

    if (!isLoggedIn) {
      return const _ListMessage(
        icon: Icons.list_alt_outlined,
        message: 'Connect your AniList from the Profile tab',
      );
    }
    if (lists == null) {
      if (loading || error == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final lang = context.read<SettingsProvider>().language;
      return _ListMessage(
        icon: Icons.wifi_off_rounded,
        message: tr('load_error', lang),
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(tr('retry', lang)),
        ),
      );
    }
    if (lists.isEmpty) {
      final isAnime = widget.type == 'ANIME';
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isAnime ? Icons.movie_filter_outlined : Icons.menu_book_outlined,
                size: 64,
                color: cs.onSurface.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 16),
              Text(
                isAnime ? 'Your anime list is empty' : 'Your manga list is empty',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 8),
              Text(
                isAnime
                    ? 'Start tracking anime you\'re watching or plan to watch'
                    : 'Start tracking manga you\'re reading or plan to read',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.35),
                    height: 1.5),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => MainNavigation.navigateToTab(2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.explore_outlined,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        isAnime ? 'Discover Anime' : 'Discover Manga',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final lang = context.read<SettingsProvider>().language;
    final labels =
        widget.type == 'ANIME' ? _animeStatusLabels(lang) : _mangaStatusLabels(lang);

    // Build a flat item list: headers + entries (only when expanded)
    final items = <({bool isHeader, String? status, String? label, int? count, Map<String, dynamic>? entry, bool isCustom})>[];
    for (final status in _statusOrder) {
      final raw = lists[status];
      if (raw == null || raw.isEmpty) continue;
      final filtered = _filterEntries(raw);
      if (filtered.isEmpty) continue;
      items.add((isHeader: true, status: status, label: labels[status] ?? status, count: filtered.length, entry: null, isCustom: false));
      if (!_collapsedSections.contains(status)) {
        for (final e in filtered) {
          items.add((isHeader: false, status: null, label: null, count: null, entry: e, isCustom: false));
        }
        items.add((isHeader: false, status: null, label: null, count: null, entry: null, isCustom: false)); // spacer
      }
    }

    // Custom list sections
    final customKeys = lists.keys.where((k) => k.startsWith(customListPrefix)).toList();
    if (customKeys.isNotEmpty && items.isNotEmpty) {
      items.add((isHeader: false, status: null, label: null, count: null, entry: null, isCustom: false));
    }
    for (final key in customKeys) {
      final raw = lists[key]!;
      final filtered = _filterEntries(raw);
      if (filtered.isEmpty) continue;
      final name = key.substring('custom:'.length);
      items.add((isHeader: true, status: key, label: name, count: filtered.length, entry: null, isCustom: true));
      if (!_collapsedSections.contains(key)) {
        for (final e in filtered) {
          items.add((isHeader: false, status: null, label: null, count: null, entry: e, isCustom: false));
        }
        items.add((isHeader: false, status: null, label: null, count: null, entry: null, isCustom: false));
      }
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 52,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text(
              widget.searchQuery.isNotEmpty
                  ? 'No results for "${widget.searchQuery}"'
                  : 'No entries match the selected genres',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                  fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          if (item.isHeader) {
            final collapsed = _collapsedSections.contains(item.status);
            return InkWell(
              onTap: () => setState(() {
                if (collapsed) {
                  _collapsedSections.remove(item.status);
                } else {
                  _collapsedSections.add(item.status!);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    if (item.isCustom) ...[
                      const Icon(Icons.playlist_add_check, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                    ],
                    Text(item.label!,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${item.count}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ],
                ),
              ),
            );
          }
          if (item.entry == null) return const SizedBox(height: 4);
          final mediaId = item.entry!['media']?['id'] as int?;
          final entryId = item.entry!['id'] as int?;
          return _SwipeableRow(
            key: ValueKey(mediaId ?? entryId ?? i),
            entry: item.entry!,
            type: widget.type,
            onAddEpisode: () => _changeProgress(item.entry!, 1),
            onRemove: () => _changeProgress(item.entry!, -1),
          );
        },
      ),
    );
  }
}

class _ListMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;
  const _ListMessage({required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.grey)),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      );
}

// ─── Swipeable Row ──────────────────────────────────────────────────────────

class _SwipeableRow extends StatefulWidget {
  final Map<String, dynamic> entry;
  final String type;
  final VoidCallback onAddEpisode;
  final VoidCallback onRemove;
  const _SwipeableRow({
    super.key,
    required this.entry,
    required this.type,
    required this.onAddEpisode,
    required this.onRemove,
  });

  @override
  State<_SwipeableRow> createState() => _SwipeableRowState();
}

class _SwipeableRowState extends State<_SwipeableRow> {
  late int _progress;

  @override
  void initState() {
    super.initState();
    _progress = (widget.entry['progress'] as num?)?.toInt() ?? 0;
  }

  @override
  void didUpdateWidget(_SwipeableRow old) {
    super.didUpdateWidget(old);
    final next = (widget.entry['progress'] as num?)?.toInt() ?? 0;
    if (next != _progress) setState(() => _progress = next);
  }

  String? _timeUntilAiring(int airingAt) {
    final remaining = airingAt - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (remaining <= 0) return null; // already aired — hide the row
    final days = remaining ~/ 86400;
    if (days > 0) return '$days day${days == 1 ? '' : 's'}';
    final hours = remaining ~/ 3600;
    return '$hours hour${hours == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final media = widget.entry['media'] as Map<String, dynamic>? ?? {};
    final progress = (widget.entry['progress'] as num?)?.toInt() ?? 0;
    final score = (widget.entry['score'] as num?)?.toDouble() ?? 0;
    final title = settings.resolveTitle(media['title'] as Map<String, dynamic>?);
    final image = media['coverImage']?['large'] as String?;
    final total = widget.type == 'ANIME'
        ? media['episodes'] as int?
        : media['chapters'] as int?;
    final id = media['id'] as int?;
    final nextAiring = media['nextAiringEpisode'] as Map<String, dynamic>?;
    final unitLabel = widget.type == 'ANIME' ? tr('episode', lang) : tr('chapter', lang);

    return Dismissible(
      key: widget.key ?? ValueKey(id),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          widget.onAddEpisode();
          return false; // don't dismiss, just trigger the action
        } else {
          widget.onRemove();
          return false;
        }
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF4CAF50).withValues(alpha: 0.9), const Color(0xFF4CAF50).withValues(alpha: 0.0)],
            stops: const [0.0, 0.8],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.add, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 6),
            Text(
              unitLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFFF44336).withValues(alpha: 0.0), const Color(0xFFF44336).withValues(alpha: 0.9)],
            stops: const [0.2, 1.0],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              unitLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.remove, color: Colors.white, size: 20),
          ],
        ),
      ),
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: InkWell(
        onTap: id != null
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DetailScreen(animeId: id)),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: image != null
                    ? CachedNetworkImage(
                        imageUrl: image,
                        width: 80,
                        height: 115,
                        fit: BoxFit.cover,
                        memCacheWidth: 160,
                        placeholder: (_, _) => Container(
                            width: 80,
                            height: 115,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest),
                        errorWidget: (_, _, _) => Container(
                            width: 80,
                            height: 115,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest),
                      )
                    : Container(
                        width: 80,
                        height: 115,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        '$_progress${total != null ? ' / $total' : ''} ${widget.type == 'ANIME' ? tr('episodes', lang) : tr('chapters', lang)}',
                        key: ValueKey(_progress),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                    if (score > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star,
                              size: 13, color: Color(0xFFFFC107)),
                          const SizedBox(width: 3),
                          Text(
                            score.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                    Builder(builder: (_) {
                      final notes = widget.entry['notes'] as String?;
                      if (notes == null || notes.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          notes,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      );
                    }),
                    if (nextAiring != null) Builder(builder: (_) {
                      final nextEp = nextAiring['episode'] as int?;
                      final airingAtRaw = nextAiring['airingAt'];
                      if (nextEp == null || airingAtRaw == null) return const SizedBox.shrink();
                      final airingAt = (airingAtRaw as num).toInt();
                      final timeStr = _timeUntilAiring(airingAt);
                      if (timeStr == null) return const SizedBox.shrink();
                      final behindBy = (nextEp - 1) - progress;
                      final color = behindBy >= 1
                          ? const Color(0xFFFFC107)
                          : const Color(0xFF4CAF50);
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.wifi_rounded, size: 13, color: color),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Episode $nextEp airs in $timeStr',
                                style: TextStyle(fontSize: 12, color: color),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ─── Completion Dialog ─────────────────────────────────────────────────────

class _CompletionDialog extends StatefulWidget {
  final String title;
  final String? coverImage;
  final double? averageScore;
  final double initialScore;
  final String type;
  /// Saves the completion; returns whether AniList accepted it.
  final Future<bool> Function(double score) onComplete;

  const _CompletionDialog({
    required this.title,
    required this.coverImage,
    required this.averageScore,
    required this.initialScore,
    required this.type,
    required this.onComplete,
  });

  @override
  State<_CompletionDialog> createState() => _CompletionDialogState();
}

class _CompletionDialogState extends State<_CompletionDialog> {
  late final ConfettiController _confetti;
  double _score = 0;
  bool _completing = false;

  static const _colors = [
    Color(0xFF02A9FF),
    Colors.white,
    Color(0xFFFFC107),
    Color(0xFFFF6B6B),
    Color(0xFF66BB6A),
    Color(0xFFCE93D8),
  ];

  @override
  void initState() {
    super.initState();
    _score = widget.initialScore;
    _confetti = ConfettiController(duration: const Duration(milliseconds: 2500));
    _confetti.play();
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    setState(() => _completing = true);
    final ok = await widget.onComplete(_score);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      return;
    }
    // Keep the dialog open so the user can retry instead of losing the change.
    setState(() => _completing = false);
    final lang = context.read<SettingsProvider>().language;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('save_failed', lang))),
    );
  }

  void _openScorePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ScorePickerSheet(
        initialScore: _score,
        onUpdate: (score) {
          setState(() => _score = score);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unitLabel = widget.type == 'ANIME' ? 'series' : 'manga';

    // Back is blocked while saving so the list can't be swiped mid-request.
    return PopScope(
      canPop: !_completing,
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Blurred cover art background
          if (widget.coverImage != null)
            Positioned.fill(
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: widget.coverImage!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  Container(color: Colors.black.withValues(alpha: 0.78)),
                ],
              ),
            ),

          // Confetti — top left
          Align(
            alignment: Alignment.topLeft,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirection: pi / 3,
              blastDirectionality: BlastDirectionality.directional,
              emissionFrequency: 0.06,
              numberOfParticles: 12,
              gravity: 0.12,
              colors: _colors,
            ),
          ),

          // Confetti — top right
          Align(
            alignment: Alignment.topRight,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirection: 2 * pi / 3,
              blastDirectionality: BlastDirectionality.directional,
              emissionFrequency: 0.06,
              numberOfParticles: 12,
              gravity: 0.12,
              colors: _colors,
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white54, size: 22),
                    ),
                  ),
                ),

                const Spacer(),

                // Congrats subtitle
                Text(
                  'Congrats! You\'ve just finished',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 10),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 28),

                // Cover image
                if (widget.coverImage != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: widget.coverImage!,
                      width: 148,
                      height: 210,
                      fit: BoxFit.cover,
                      memCacheWidth: 296,
                    ),
                  ),
                const SizedBox(height: 28),

                // Rating question
                Text(
                  'What\'s your final rating for this $unitLabel?',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 12),

                // Score button
                GestureDetector(
                  onTap: _openScorePicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Text(
                      _score > 0 ? _score.toStringAsFixed(1) : 'Not Scored',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // Average rating
                if (widget.averageScore != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFC107)),
                      const SizedBox(width: 4),
                      Text(
                        'AVERAGE RATING  ${(widget.averageScore! / 10).toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.5,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ],

                const Spacer(),

                // Complete button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: GestureDetector(
                    onTap: _completing ? null : _complete,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 56,
                      decoration: BoxDecoration(
                        color: _completing
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Center(
                        child: _completing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Complete ${widget.type == 'ANIME' ? 'Series' : 'Manga'}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
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

// ─── Score Picker Sheet ────────────────────────────────────────────────────

class _ScorePickerSheet extends StatefulWidget {
  final double initialScore;
  final void Function(double) onUpdate;

  const _ScorePickerSheet({required this.initialScore, required this.onUpdate});

  @override
  State<_ScorePickerSheet> createState() => _ScorePickerSheetState();
}

class _ScorePickerSheetState extends State<_ScorePickerSheet> {
  late double _score;
  late final TextEditingController _ctrl;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _score = widget.initialScore;
    _ctrl = TextEditingController(text: _fmt(_score));
    _focusNode.addListener(_onFocusLost);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusLost);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double v) => v == 0 ? '0' : v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

  void _onFocusLost() {
    if (!_focusNode.hasFocus) _applyText();
  }

  void _applyText() {
    final parsed = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    final clamped = (parsed ?? _score).clamp(0.0, 10.0);
    setState(() => _score = clamped);
    _ctrl.text = _fmt(clamped);
  }

  void _adjust(double delta) {
    _focusNode.unfocus();
    final next = (_score + delta).clamp(0.0, 10.0);
    setState(() => _score = next);
    _ctrl.text = _fmt(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            'Score',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Minus
              GestureDetector(
                onTap: () => _adjust(-0.5),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.remove, size: 26, color: cs.onSurface),
                ),
              ),
              const SizedBox(width: 16),
              // Score — editable field
              Container(
                width: 120,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focusNode,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _applyText(),
                  onEditingComplete: _applyText,
                ),
              ),
              const SizedBox(width: 16),
              // Plus
              GestureDetector(
                onTap: () => _adjust(0.5),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, size: 26, color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: () {
                _applyText();
                widget.onUpdate(_score);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text(
                'Update',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
