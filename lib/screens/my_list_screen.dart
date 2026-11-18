import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:provider/provider.dart';
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
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_text.dart';
import '../widgets/app_refresh_indicator.dart';
import '../widgets/app_sheet.dart';
import '../widgets/genre_filter_sheet.dart' show FilterOptionChip;
import '../widgets/app_button.dart';
import '../widgets/media_preview.dart';
import '../widgets/motion/animated_count.dart';
import '../widgets/motion/cover_hero.dart';
import '../widgets/motion/fade_switcher.dart';
import '../widgets/motion/press_scale.dart';
import '../widgets/motion/rounded_hero.dart';
import '../widgets/motion/staggered_entrance.dart';
import '../widgets/motion/progress_moment.dart';
import '../widgets/option_sheet.dart';
import '../widgets/skeletons.dart';
import '../widgets/state_message.dart';
import '../widgets/entry_editor/entry_editor_sheet.dart';
import '../widgets/motion/swipe_action.dart';
import '../widgets/motion/pressable.dart';
import 'completion_celebration.dart';
import 'settings_screen.dart';
import '../services/notification_service.dart';
import '../widgets/load_error_view.dart';
import '../widgets/app_image.dart';

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
    final lang = context.read<SettingsProvider>().language;
    showAppSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(tr('list_filter_by_genre', lang), style: AppText.headline),
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
                children: [
                  for (final genre in _genreKeys.entries)
                    FilterOptionChip(
                      label: tr(genre.value, lang),
                      selected: _activeGenres.contains(genre.key),
                      onTap: () {
                        setState(() {
                          _activeGenres = _activeGenres.contains(genre.key)
                              ? _activeGenres.difference({genre.key})
                              : {..._activeGenres, genre.key};
                        });
                        setSheet(() {});
                      },
                    ),
                ],
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
        leading: _ProfileAvatarButton(avatar: avatar, name: auth.user?['name'] as String?, lang: lang),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _activeGenres.isNotEmpty,
              label: Text('${_activeGenres.length}'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              textColor: Theme.of(context).colorScheme.onPrimary,
              child: Icon(
                Icons.tune_rounded,
                size: 22,
                color: _activeGenres.isNotEmpty
                    ? Theme.of(context).colorScheme.primary
                    : context.colors.textSecondary,
              ),
            ),
            onPressed: () => _showGenreFilter(context),
            tooltip: tr('filters', lang),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Icon(Icons.swap_vert, color: context.colors.textSecondary, size: 22),
              tooltip: tr('search_sort', lang),
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
                prefixIcon: Icon(Icons.search, size: 20, color: context.colors.textSecondary),
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
    await showCompletionCelebration(
      context,
      title: title,
      coverUrl: coverImage,
      averageScore: averageScore,
      initialScore: initialScore,
      isManga: widget.type != 'ANIME',
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
      return StateMessage(
        key: const ValueKey('list-logged-out'),
        icon: Icons.list_alt_outlined,
        message: tr('list_connect_prompt', lang),
      );
    }
    if (lists == null) {
      if (loading || error == null) {
        return const ListSkeleton(key: ValueKey('list-skeleton'));
      }
      return LoadErrorView(key: const ValueKey('list-error'), onRetry: _load);
    }
    if (lists.isEmpty) {
      final isAnime = widget.type == 'ANIME';
      return StateMessage(
        key: const ValueKey('list-empty'),
        icon: isAnime ? Icons.movie_filter_outlined : Icons.menu_book_outlined,
        title: tr(isAnime ? 'list_empty_anime' : 'list_empty_manga', lang),
        message: tr(isAnime ? 'list_empty_anime_hint' : 'list_empty_manga_hint', lang),
        action: AppButton(
          label: tr(isAnime ? 'list_discover_anime' : 'list_discover_manga', lang),
          icon: Icons.explore_outlined,
          onPressed: () => MainNavigation.navigateToTab(2),
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
        : StateMessage(
            icon: Icons.search_off_rounded,
            message: widget.searchQuery.isNotEmpty
                ? trf('list_no_results_for', lang, {'query': widget.searchQuery})
                : tr('list_no_genre_match', lang),
          );

    // The first rows cascade in when the list first appears; rows built
    // later (scrolling, filtering, expanding a section) appear at once.
    return EntranceGate(
      key: const ValueKey('list'),
      trigger: widget.type,
      child: noMatch ?? AppRefreshIndicator(
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
              Icon(Icons.playlist_add_check, size: 16, color: context.colors.textSecondary),
              const SizedBox(width: 6),
            ],
            Text(label, style: AppText.subhead),
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
            // Turns to point at the folded section instead of swapping icons.
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: AppMotion.of(context, AppMotion.short),
              curve: AppMotion.standard,
              child: Icon(Icons.expand_more, color: context.colors.textSecondary, size: 20),
            ),
          ],
        ),
      ),
    );
  }
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

    final cover = RoundedHero(
      tag: heroTag,
      borderRadius: BorderRadius.circular(6),
      child: AppImage(url: image, cacheWidth: 160, width: 80, height: 115),
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
    final finished = total != null && total > 0 && _progress >= total;

    // A quarter of the row is enough: right adds one, left takes one away.
    return SwipeAction(
      startToEnd: SwipeActionSide(
        color: const Color(0xFF4CAF50),
        icon: Icons.add,
        label: unitLabel,
        onTriggered: widget.onAddEpisode,
      ),
      endToStart: SwipeActionSide(
        color: const Color(0xFFF44336),
        icon: Icons.remove,
        label: unitLabel,
        onTriggered: widget.onRemove,
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
        // Holding the row shows what it is; the editor is a tap from there.
        onLongPress: id == null
            ? widget.onEdit
            : () => showMediaPreview(context, media: media, isManga: widget.type != 'ANIME', onEdit: widget.onEdit),
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
                          children: [
                            // Seen to the end: a check instead of a full
                            // line under every finished title, centred on
                            // the text (an icon has no baseline of its own).
                            if (finished) ...[
                              Icon(
                                Icons.task_alt_rounded,
                                key: const ValueKey('progress-finished'),
                                size: 13,
                                color: context.colors.success,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
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
                            // Answers a swipe where the eye already is,
                            // without moving the line it sits on.
                            ChangeTick(value: _progress),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: AppMotion.of(context, AppMotion.medium),
                      curve: AppMotion.standard,
                      alignment: Alignment.topCenter,
                      child: total != null && total > 0 && !finished
                          ? Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: ProgressLine(value: _progress, total: total),
                            )
                          : const SizedBox(width: double.infinity),
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

/// The user's avatar at the top left. A tap opens the profile, which grows
/// out of this corner; holding it offers the profile and settings.
class _ProfileAvatarButton extends StatelessWidget {
  const _ProfileAvatarButton({required this.avatar, required this.name, required this.lang});

  final String? avatar;
  final String? name;
  final String lang;

  static const _profileTab = 4;

  void _openProfile() => MainNavigation.navigateToTab(_profileTab, from: Alignment.topLeft);

  void _showMenu(BuildContext context) {
    mediumHaptic();
    showOptionSheet<String>(
      context: context,
      title: name ?? tr('nav_profile', lang),
      options: const ['profile', 'settings'],
      labelOf: (option) => tr(option == 'profile' ? 'nav_profile' : 'settings', lang),
      iconOf: (option) => option == 'profile' ? Icons.person_outline_rounded : Icons.settings_outlined,
      current: '',
      onSelected: (option) {
        if (option == 'profile') {
          _openProfile();
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final picture = avatar;
    return Semantics(
      button: true,
      label: tr('nav_profile', lang),
      excludeSemantics: true,
      child: Pressable(
        pressedScale: 0.85,
        onTap: () {
          lightHaptic();
          _openProfile();
        },
        onLongPress: () => _showMenu(context),
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.5),
              ),
              child: ClipOval(
                child: SizedBox.square(
                  dimension: 30,
                  child: AppImage(
                    url: picture,
                    cacheWidth: 64,
                    placeholder: const Icon(Icons.person, size: 16, color: Colors.grey),
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
