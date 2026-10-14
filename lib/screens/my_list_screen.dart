import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:confetti/confetti.dart';
import '../providers/media_list_store.dart';
import '../services/auth_service.dart';
import '../screens/detail_screen.dart';
import '../main.dart';
import '../providers/settings_provider.dart';
import '../utils/haptics.dart';
import '../utils/translations.dart' show tr, trf;
import '../utils/refresh_notifier.dart';
import '../utils/score_utils.dart';
import '../utils/tab_reselect.dart';
import '../theme/app_motion.dart';
import '../widgets/motion/animated_count.dart';
import '../widgets/motion/cover_hero.dart';
import '../widgets/motion/fade_switcher.dart';
import '../widgets/motion/press_scale.dart';
import '../widgets/motion/rounded_hero.dart';
import '../widgets/motion/staggered_entrance.dart';
import '../widgets/option_sheet.dart';
import '../widgets/skeletons.dart';
import '../widgets/entry_editor/entry_editor_sheet.dart';
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

  /// AniList genre names (matched against the entries as is) and their
  /// display keys.
  static const _genreKeys = {
    'Action': 'search_genre_action',
    'Adventure': 'search_genre_adventure',
    'Comedy': 'search_genre_comedy',
    'Drama': 'search_genre_drama',
    'Ecchi': 'search_genre_ecchi',
    'Fantasy': 'search_genre_fantasy',
    'Horror': 'search_genre_horror',
    'Mahou Shoujo': 'search_genre_mahou_shoujo',
    'Mecha': 'search_genre_mecha',
    'Music': 'search_genre_music',
    'Mystery': 'search_genre_mystery',
    'Psychological': 'search_genre_psychological',
    'Romance': 'search_genre_romance',
    'Sci-Fi': 'search_genre_sci_fi',
    'Slice of Life': 'search_genre_slice_of_life',
    'Sports': 'search_genre_sports',
    'Supernatural': 'search_genre_supernatural',
    'Thriller': 'search_genre_thriller',
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showGenreFilter(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lang = context.read<SettingsProvider>().language;
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
                  Text(tr('list_filter_by_genre', lang),
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
                      child: Text(tr('clear', lang),
                          style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _genreKeys.entries.map((genre) {
                  final g = genre.key;
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
                      duration: AppMotion.of(ctx, AppMotion.short),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? cs.primary : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? cs.primary : cs.outline.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        tr(genre.value, lang),
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
            child: IconButton(
              icon: const Icon(Icons.swap_vert, color: Colors.grey, size: 22),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => showOptionSheet<_SortMode>(
                context: context,
                title: tr('search_sort', lang),
                options: _SortMode.values,
                labelOf: (mode) => switch (mode) {
                  _SortMode.lastUpdated => tr('last_updated', lang),
                  _SortMode.alphabetical => tr('alphabetical', lang),
                  _SortMode.ratingHigh => tr('rating_high', lang),
                  _SortMode.ratingLow => tr('rating_low', lang),
                },
                iconOf: (mode) => switch (mode) {
                  _SortMode.lastUpdated => Icons.history,
                  _SortMode.alphabetical => Icons.sort_by_alpha,
                  _SortMode.ratingHigh => Icons.star,
                  _SortMode.ratingLow => Icons.star_outline,
                },
                current: _sortMode,
                onSelected: (mode) => setState(() => _sortMode = mode),
              ),
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
  final _scrollController = ScrollController();
  late final VoidCallback _stopReselectListener;

  /// This list's index in the bottom navigation.
  int get _tab => widget.type == 'ANIME' ? 0 : 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _auth = context.read<AuthService>()..addListener(_onAuthChanged);
      _load();
    });
    listRefreshNotifier.addListener(_onRefreshRequested);
    _stopReselectListener = scrollToTopOnReselect(
      tabReselectedNotifier,
      tab: _tab,
      onReselected: () => scrollToTop(_scrollController, animate: !AppMotion.reduced(context)),
    );
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    listRefreshNotifier.removeListener(_onRefreshRequested);
    _stopReselectListener();
    _scrollController.dispose();
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
        // Flutter keeps a snack bar with an action (Undo) until it's
        // dismissed; this one should still go away after [duration].
        persist: false,
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
    // An Undo for an earlier change must not stay tappable while this one saves.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    selectionHaptic();

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
    final unitKey = widget.type == 'ANIME' ? 'list_episode_n' : 'list_chapter_n';
    _showSnack(
      '$title · ${trf(unitKey, lang, {'n': newProgress})}',
      action: SnackBarAction(
        label: tr('undo', lang),
        onPressed: () => _undoProgress(mediaId, progress),
      ),
    );
  }

  /// Opens the full entry editor for a row (long-press). The editor reads
  /// the fields the list doesn't load before showing them, and a save
  /// updates the shared store this list is built from.
  void _openEditor(Map<String, dynamic> entry) {
    final media = EditorMedia.fromMedia(
      entry['media'] as Map<String, dynamic>?,
      isManga: widget.type == 'MANGA',
    );
    if (media == null) return;
    mediumHaptic();
    // Entries only know their status through the list they're in.
    final status = context
        .read<MediaListStore>()
        .listsOf(widget.type)
        ?.entries
        .where((list) =>
            !list.key.startsWith(customListPrefix) &&
            list.value.any((e) => (e['media'] as Map?)?['id'] == media.id))
        .map((list) => list.key)
        .firstOrNull;
    showEntryEditor(context, media: media, entry: {...entry, 'status': ?status});
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
      transitionDuration: AppMotion.of(context, AppMotion.long),
      transitionBuilder: (ctx, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.exit),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.exit)),
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
    // Each state is keyed, so loading, errors and the list cross-fade.
    return FadeSwitcher(child: _content(context));
  }

  Widget _content(BuildContext context) {
    final lang = context.select<SettingsProvider, String>((s) => s.language);
    final isLoggedIn = context.select<AuthService, bool>((auth) => auth.isLoggedIn);
    final (lists, loading, error) = context.select<MediaListStore, (MediaLists?, bool, Object?)>(
        (store) => (store.listsOf(widget.type), store.isLoading(widget.type), store.errorOf(widget.type)));

    if (!isLoggedIn) {
      return _ListMessage(
        key: const ValueKey('list-logged-out'),
        icon: Icons.list_alt_outlined,
        message: tr('list_connect_prompt', lang),
      );
    }
    if (lists == null) {
      if (loading || error == null) {
        return const ListSkeleton(key: ValueKey('list-skeleton'));
      }
      return _ListMessage(
        key: const ValueKey('list-error'),
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
        key: const ValueKey('list-empty'),
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
                tr(isAnime ? 'list_empty_anime' : 'list_empty_manga', lang),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 8),
              Text(
                tr(isAnime ? 'list_empty_anime_hint' : 'list_empty_manga_hint', lang),
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
                        tr(isAnime ? 'list_discover_anime' : 'list_discover_manga', lang),
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

    final labels =
        widget.type == 'ANIME' ? _animeStatusLabels(lang) : _mangaStatusLabels(lang);

    // Build a flat item list: headers + entries (only when expanded). An
    // entry's status is the section it's shown in (a media can also be in
    // custom lists), which keeps its cover hero unique.
    final items = <({bool isHeader, String? status, String? label, int? count, Map<String, dynamic>? entry, bool isCustom})>[];
    for (final status in _statusOrder) {
      final raw = lists[status];
      if (raw == null || raw.isEmpty) continue;
      final filtered = _filterEntries(raw);
      if (filtered.isEmpty) continue;
      items.add((isHeader: true, status: status, label: labels[status] ?? status, count: filtered.length, entry: null, isCustom: false));
      if (!_collapsedSections.contains(status)) {
        for (final e in filtered) {
          items.add((isHeader: false, status: status, label: null, count: null, entry: e, isCustom: false));
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
          items.add((isHeader: false, status: key, label: null, count: null, entry: e, isCustom: false));
        }
        items.add((isHeader: false, status: null, label: null, count: null, entry: null, isCustom: false));
      }
    }

    // "No match" shares the list's gate and key, so typing between results
    // and none swaps them at once instead of cross-fading the whole list
    // and replaying its cascade on every keystroke.
    final noMatch = items.isNotEmpty
        ? null
        : Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 52,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text(
              widget.searchQuery.isNotEmpty
                  ? trf('list_no_results_for', lang, {'query': widget.searchQuery})
                  : tr('list_no_genre_match', lang),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                  fontSize: 13)),
          ],
        ),
      );

    // The first rows cascade in when the list first appears; rows built
    // later (scrolling, filtering, expanding a section) appear at once.
    return EntranceGate(
      key: const ValueKey('list'),
      trigger: widget.type,
      child: noMatch ?? RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            if (item.isHeader) {
              return StaggeredEntrance(
                index: i,
                child: _sectionHeader(context, item.status!, item.label!, item.count!, isCustom: item.isCustom),
              );
            }
            final entry = item.entry;
            if (entry == null) return const SizedBox(height: 4);
            final mediaId = entry['media']?['id'] as int?;
            final entryId = entry['id'] as int?;
            return StaggeredEntrance(
              index: i,
              child: _SwipeableRow(
                key: ValueKey(mediaId ?? entryId ?? i),
                entry: entry,
                type: widget.type,
                heroScope: 'mylist-${widget.type}-${item.status}',
                onAddEpisode: () => _changeProgress(entry, 1),
                onRemove: () => _changeProgress(entry, -1),
                onEdit: () => _openEditor(entry),
              ),
            );
          },
        ),
      ),
    );
  }

  /// A section's title and size; tapping it collapses or expands it.
  Widget _sectionHeader(BuildContext context, String section, String label, int count, {required bool isCustom}) {
    final collapsed = _collapsedSections.contains(section);
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () => setState(() {
        if (collapsed) {
          _collapsedSections.remove(section);
        } else {
          _collapsedSections.add(section);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (isCustom) ...[
              const Icon(Icons.playlist_add_check, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: primary),
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
}

class _ListMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;
  const _ListMessage({super.key, required this.icon, required this.message, this.action});

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

  /// The list section the row is in, for its cover's hero tag: unique on
  /// the screen even when a media is also in custom lists.
  final String heroScope;
  final VoidCallback onAddEpisode;
  final VoidCallback onRemove;
  /// Opens the full entry editor (long-press).
  final VoidCallback onEdit;
  const _SwipeableRow({
    super.key,
    required this.entry,
    required this.type,
    required this.heroScope,
    required this.onAddEpisode,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  State<_SwipeableRow> createState() => _SwipeableRowState();
}

class _SwipeableRowState extends State<_SwipeableRow> {
  late int _progress;

  // Press feedback lives on the cover only: the row itself must stay still
  // under the swipe and long-press gestures.
  final _pressed = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _progress = (widget.entry['progress'] as num?)?.toInt() ?? 0;
  }

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_SwipeableRow old) {
    super.didUpdateWidget(old);
    final next = (widget.entry['progress'] as num?)?.toInt() ?? 0;
    if (next != _progress) setState(() => _progress = next);
  }

  /// The cover, which flies to the detail page and dips while the row is
  /// pressed (a transform only, so the row never re-lays out).
  Widget _cover(BuildContext context, String? image, String? heroTag) {
    final placeholder = Container(
        width: 80,
        height: 115,
        color: Theme.of(context).colorScheme.surfaceContainerHighest);
    final cover = RoundedHero(
      tag: heroTag,
      borderRadius: BorderRadius.circular(6),
      child: image != null
          ? CachedNetworkImage(
              imageUrl: image,
              width: 80,
              height: 115,
              fit: BoxFit.cover,
              memCacheWidth: 160,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            )
          : placeholder,
    );
    return PressScale(pressed: _pressed, child: cover);
  }

  String? _timeUntilAiring(int airingAt, String lang) {
    final remaining = airingAt - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (remaining <= 0) return null; // already aired — hide the row
    final days = remaining ~/ 86400;
    if (days > 0) {
      return trf(days == 1 ? 'list_airs_day' : 'list_airs_days', lang, {'n': days});
    }
    final hours = remaining ~/ 3600;
    return trf(hours == 1 ? 'list_airs_hour' : 'list_airs_hours', lang, {'n': hours});
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final media = widget.entry['media'] as Map<String, dynamic>? ?? {};
    final progress = (widget.entry['progress'] as num?)?.toInt() ?? 0;
    final score = (widget.entry['score'] as num?)?.toDouble() ?? 0;
    final scoreFormat = context.select<AuthService, String?>((a) => scoreFormatOf(a.user));
    final title = settings.resolveTitle(media['title'] as Map<String, dynamic>?);
    final image = media['coverImage']?['large'] as String?;
    final total = widget.type == 'ANIME'
        ? media['episodes'] as int?
        : media['chapters'] as int?;
    final id = media['id'] as int?;
    final heroTag = id == null ? null : coverHeroTag(widget.heroScope, id);
    final nextAiring = media['nextAiringEpisode'] as Map<String, dynamic>?;
    final unitLabel = widget.type == 'ANIME' ? tr('episode', lang) : tr('chapter', lang);
    final progressSuffix =
        '${total != null ? ' / $total' : ''} ${widget.type == 'ANIME' ? tr('episodes', lang) : tr('chapters', lang)}';

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
        // Screen readers can't discover a long press, so the editor is also
        // offered as a named action.
        child: Semantics(
        onLongPressHint: tr('tooltip_edit_entry', lang),
        customSemanticsActions: {
          CustomSemanticsAction(label: tr('tooltip_edit_entry', lang)): widget.onEdit,
        },
        child: InkWell(
        onTap: id != null
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DetailScreen(
                            animeId: id,
                            heroTag: heroTag,
                            initialCoverUrl: image,
                          )),
                )
            : null,
        onLongPress: widget.onEdit,
        onHighlightChanged: (pressed) => _pressed.value = pressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cover(context, image, heroTag),
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
                    // Only the number rolls when a swipe or edit changes it;
                    // screen readers still hear one phrase.
                    Semantics(
                      label: '$_progress$progressSuffix',
                      excludeSemantics: true,
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            AnimatedCount(value: _progress),
                            Flexible(child: Text(progressSuffix)),
                          ],
                        ),
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
                            formatScore(score, scoreFormat),
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
                      final timeStr = _timeUntilAiring(airingAt, lang);
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
                                trf('list_airs_in', lang, {'n': nextEp, 'time': timeStr}),
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
  bool _confettiStarted = false;
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // One burst when the dialog opens, skipped when animations are reduced.
    if (_confettiStarted) return;
    _confettiStarted = true;
    if (!AppMotion.reduced(context)) _confetti.play();
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
    final lang = context.watch<SettingsProvider>().language;
    final isAnime = widget.type == 'ANIME';

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
                    // A darkened backdrop: a small decode is plenty.
                    memCacheWidth: 300,
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
                  tr('list_congrats_finished', lang),
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
                  tr(isAnime ? 'list_final_rating_series' : 'list_final_rating_manga', lang),
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
                      _score > 0 ? _score.toStringAsFixed(1) : tr('list_not_scored', lang),
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
                        trf('list_average_rating', lang,
                            {'score': (widget.averageScore! / 10).toStringAsFixed(1)}),
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
                                tr(isAnime ? 'list_complete_series' : 'list_complete_manga', lang),
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
    final lang = context.watch<SettingsProvider>().language;

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
            tr('list_score', lang),
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
              child: Text(
                tr('list_update', lang),
                style: const TextStyle(
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
