import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/api_cache.dart';
import '../services/people_api.dart';
import '../utils/review_text.dart';
import '../utils/translations.dart';
import '../widgets/detail/load_error_view.dart';
import '../widgets/detail/section_title.dart';
import '../widgets/overlay_button.dart';
import '../widgets/people/expandable_text.dart';
import '../widgets/people/info_pill.dart';
import '../widgets/people/media_cover_tile.dart';
import '../widgets/people/paged_items.dart';
import '../widgets/people/people_labels.dart';
import '../widgets/people/people_routes.dart';
import '../widgets/people/voiced_character_tile.dart';
import '../widgets/skeletons.dart';

/// A staff member's page (voice actor, director, mangaka…): who they are,
/// the characters they voiced and their staff credits, loading more of
/// either list on scroll.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.staffId, this.name, this.imageUrl, this.api});

  final int staffId;

  /// Shown until the page loads (from the card that opened it).
  final String? name;
  final String? imageUrl;

  /// Replaces the AniList API, for tests.
  final PeopleApi? api;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

enum _StaffTab { characters, roles }

class _StaffScreenState extends State<StaffScreen> with PagedLoading {
  // Public and slow-changing, so a recent copy isn't refetched.
  static const _maxAge = Duration(hours: 6);
  // Starts loading the next page this close to the end of the list.
  static const _loadMoreExtent = 600.0;

  late final PeopleApi _api = widget.api ?? PeopleApi();
  final _scroll = ScrollController();

  StaffDetail? _staff;
  bool _loading = true;
  PagedItems<VoicedCharacter> _characters = const PagedItems();
  PagedItems<StaffRole> _roles = const PagedItems();

  /// The list the viewer picked; null shows the default one.
  _StaffTab? _pickedTab;

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

  static StaffDetail _decode(Object? json) =>
      StaffDetail.fromJson(json) ?? (throw const FormatException('Not a cached staff member'));

  Future<void> _load({bool force = false}) async {
    final staffId = widget.staffId;
    try {
      await context.read<ApiCache>().load<StaffDetail>(
            key: 'staff:$staffId',
            fetch: () => _api.getStaff(staffId),
            decode: _decode,
            onData: (staff, {required isFresh}) {
              if (!mounted) return;
              resetPaging();
              setState(() {
                _staff = staff;
                _characters = PagedItems.firstPage(
                  staff.characters.items,
                  hasNextPage: staff.characters.hasNextPage,
                );
                _roles = PagedItems.firstPage(staff.roles.items, hasNextPage: staff.roles.hasNextPage);
              });
              WidgetsBinding.instance.addPostFrameCallback((_) => loadMoreIfNearEnd());
            },
            maxAge: _maxAge,
            force: force,
          );
    } on Exception catch (e) {
      debugPrint('[StaffScreen] Loading staff $staffId failed: $e');
      if (force && mounted && _staff != null) _showLoadError();
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

  /// The list on screen: the one picked, else the one with more on its
  /// first page (voiced characters for voice actors, credits for the rest).
  _StaffTab? get _tab {
    final hasCharacters = _characters.items.isNotEmpty;
    final hasRoles = _roles.items.isNotEmpty;
    if (hasCharacters && hasRoles) {
      return _pickedTab ??
          (_characters.items.length >= _roles.items.length ? _StaffTab.characters : _StaffTab.roles);
    }
    if (hasCharacters) return _StaffTab.characters;
    if (hasRoles) return _StaffTab.roles;
    return null;
  }

  @override
  void loadMoreIfNearEnd() {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter > _loadMoreExtent) return;
    switch (_tab) {
      case _StaffTab.characters:
        if (_characters.canLoadMore) _loadMoreCharacters();
      case _StaffTab.roles:
        if (_roles.canLoadMore) _loadMoreRoles();
      case null:
        break;
    }
  }

  void _loadMoreCharacters({bool retry = false}) => unawaited(loadNextPage<VoicedCharacter>(
        read: () => _characters,
        write: (value) => _characters = value,
        fetch: (page) async {
          final result = await _api.getVoicedCharacters(widget.staffId, page: page);
          return (result.items, result.hasNextPage);
        },
        merge: appendVoicedCharacters,
        debugLabel: 'StaffScreen characters of ${widget.staffId}',
        retry: retry,
      ));

  void _loadMoreRoles({bool retry = false}) => unawaited(loadNextPage<StaffRole>(
        read: () => _roles,
        write: (value) => _roles = value,
        fetch: (page) async {
          final result = await _api.getStaffRoles(widget.staffId, page: page);
          return (result.items, result.hasNextPage);
        },
        merge: appendStaffRoles,
        debugLabel: 'StaffScreen roles of ${widget.staffId}',
        retry: retry,
      ));

  void _pickTab(_StaffTab tab) {
    setState(() => _pickedTab = tab);
    WidgetsBinding.instance.addPostFrameCallback((_) => loadMoreIfNearEnd());
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Scaffold(
      body: Stack(
        children: [
          _body(lang),
          // 44px touch target around a 36px circle, so the offset is 4px smaller.
          Positioned(
            top: MediaQuery.paddingOf(context).top + 2,
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

  Widget _body(String lang) {
    final staff = _staff;
    if (staff == null) {
      return _loading ? const _StaffSkeleton() : LoadErrorView(onRetry: _retry);
    }
    final description = cleanReviewText(staff.description, spoilerPlaceholder: tr('review_spoiler', lang));
    final facts = _facts(staff, lang);
    return RefreshIndicator(
      onRefresh: _refresh,
      // Below the status bar and the back button.
      edgeOffset: MediaQuery.paddingOf(context).top + 40,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _StaffHeader(
              staff: staff,
              name: staff.name.isNotEmpty ? staff.name : widget.name ?? '',
              imageUrl: staff.imageUrl ?? widget.imageUrl,
            ),
          ),
          if (facts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: facts),
              ),
            ),
          if (description.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DetailSectionTitle(tr('char_about', lang)),
                    const SizedBox(height: 8),
                    ExpandableText(
                      text: description,
                      expandLabel: tr('detail_read_more', lang),
                      collapseLabel: tr('char_show_less', lang),
                    ),
                  ],
                ),
              ),
            ),
          ..._lists(lang),
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom)),
        ],
      ),
    );
  }

  /// Pills with what AniList knows about them.
  List<Widget> _facts(StaffDetail staff, String lang) {
    final gender = staff.gender;
    final age = staff.age;
    final born = fuzzyDateLabel(staff.dateOfBirth, lang);
    final died = fuzzyDateLabel(staff.dateOfDeath, lang);
    final homeTown = staff.homeTown;
    final active = _yearsActive(staff.yearsActive, lang);
    final bloodType = staff.bloodType;
    final favourites = staff.favourites;
    return [
      if (gender != null) InfoPill(icon: Icons.person_outline_rounded, label: genderLabel(gender, lang)),
      if (age != null && age > 0) InfoPill(icon: Icons.cake_outlined, label: trf('staff_age', lang, {'n': age})),
      if (born != null) InfoPill(icon: Icons.calendar_today_outlined, label: born),
      if (died != null) InfoPill(icon: Icons.local_florist_outlined, label: trf('staff_died', lang, {'date': died})),
      if (homeTown != null) InfoPill(icon: Icons.place_outlined, label: homeTown),
      if (active != null) InfoPill(icon: Icons.work_outline_rounded, label: active),
      if (bloodType != null) InfoPill(icon: Icons.water_drop_outlined, label: bloodType),
      if (favourites != null && favourites > 0)
        Semantics(
          label: trf('staff_favourites', lang, {'n': favourites}),
          excludeSemantics: true,
          child: InfoPill(icon: Icons.favorite_rounded, iconColor: Colors.redAccent, label: compactCount(favourites)),
        ),
    ];
  }

  /// "Active since 1985" or "Active 1985–2010".
  String? _yearsActive(List<int> years, String lang) {
    if (years.isEmpty) return null;
    if (years.length == 1) return trf('staff_active_since', lang, {'year': years.first});
    return trf('staff_active_range', lang, {'start': years.first, 'end': years[1]});
  }

  List<Widget> _lists(String lang) {
    final tab = _tab;
    if (tab == null) return const [];
    final showsBoth = _characters.items.isNotEmpty && _roles.items.isNotEmpty;
    final list = tab == _StaffTab.characters ? _characters : _roles;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: showsBoth
              ? SegmentedButton<_StaffTab>(
                  segments: [
                    ButtonSegment(value: _StaffTab.characters, label: Text(tr('staff_voiced_characters', lang))),
                    ButtonSegment(value: _StaffTab.roles, label: Text(tr('staff_roles', lang))),
                  ],
                  selected: {tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => _pickTab(selection.first),
                )
              : DetailSectionTitle(
                  tr(tab == _StaffTab.characters ? 'staff_voiced_characters' : 'staff_roles', lang).toUpperCase(),
                ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: switch (tab) {
          _StaffTab.characters => SliverGrid.builder(
              gridDelegate: voicedCharacterGridDelegate,
              itemCount: _characters.items.length,
              itemBuilder: (context, i) {
                final item = _characters.items[i];
                return VoicedCharacterTile(
                  item: item,
                  onCharacterTap: () => openCharacter(context, item.character),
                  onMediaTap: () => openMedia(context, item.media),
                );
              },
            ),
          _StaffTab.roles => SliverGrid.builder(
              gridDelegate: mediaCoverGridDelegate,
              itemCount: _roles.items.length,
              itemBuilder: (context, i) {
                final role = _roles.items[i];
                return MediaCoverTile(
                  media: role.media,
                  subtitle: role.roles.join(', '),
                  subtitleLines: 2,
                  onTap: () => openMedia(context, role.media),
                );
              },
            ),
        },
      ),
      SliverToBoxAdapter(
        child: LoadMoreFooter(
          hasMore: list.hasNextPage,
          failed: list.failed,
          onRetry: () => tab == _StaffTab.characters
              ? _loadMoreCharacters(retry: true)
              : _loadMoreRoles(retry: true),
        ),
      ),
    ];
  }
}

/// Blurred photo backdrop with the portrait, name and occupations.
class _StaffHeader extends StatelessWidget {
  const _StaffHeader({required this.staff, required this.name, required this.imageUrl});

  static const _portraitWidth = 124.0;
  static const _portraitHeight = 180.0;
  static const _backdropHeight = 210.0;

  final StaffDetail staff;
  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.paddingOf(context).top;
    final imageUrl = this.imageUrl;
    final nativeName = staff.nativeName;
    final placeholder = Container(color: cs.surfaceContainerHighest);
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _backdropHeight + topPadding,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null)
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 240,
                      placeholder: (_, _) => const SizedBox.shrink(),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  )
                else
                  ColoredBox(color: cs.primary.withValues(alpha: 0.25)),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [cs.surface.withValues(alpha: 0.35), cs.surface],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, topPadding + 48, 24, 16),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: _portraitWidth,
                  height: _portraitHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Semantics(
                      image: true,
                      label: name,
                      child: imageUrl == null
                          ? placeholder
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              memCacheWidth: 400,
                              placeholder: (_, _) => placeholder,
                              errorWidget: (_, _, _) => placeholder,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              if (nativeName != null) ...[
                const SizedBox(height: 4),
                Text(
                  nativeName,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.55)),
                ),
              ],
              if (staff.occupations.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  staff.occupations.join(' · '),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Placeholder shaped like the header and the start of a grid.
class _StaffSkeleton extends StatelessWidget {
  const _StaffSkeleton();

  @override
  Widget build(BuildContext context) => Skeleton(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 48, 16, 0),
          child: Column(
            children: [
              const SkeletonBox(
                width: _StaffHeader._portraitWidth,
                height: _StaffHeader._portraitHeight,
                radius: 14,
              ),
              const SizedBox(height: 16),
              const SkeletonBox(width: 200, height: 20),
              const SizedBox(height: 8),
              const SkeletonBox(width: 120, height: 14),
              const SizedBox(height: 20),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  SkeletonBox(width: 90, height: 26, radius: 20),
                  SkeletonBox(width: 110, height: 26, radius: 20),
                  SkeletonBox(width: 70, height: 26, radius: 20),
                ],
              ),
              const SizedBox(height: 28),
              for (var row = 0; row < 2; row++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(child: SkeletonBox(height: 180, radius: 12)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBox(height: 180, radius: 12)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}
