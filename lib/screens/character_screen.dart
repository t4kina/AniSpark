import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/anilist_service.dart';
import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../services/people_api.dart';
import '../theme/app_motion.dart';
import '../utils/haptics.dart';
import '../utils/refresh_notifier.dart';
import '../utils/review_text.dart';
import '../utils/translations.dart' show tr;
import '../widgets/motion/cover_hero.dart';
import '../widgets/motion/fade_switcher.dart';
import '../widgets/motion/pop_on_change.dart';
import '../widgets/motion/pressable.dart';
import '../widgets/motion/rounded_hero.dart';
import '../widgets/overlay_button.dart';
import '../widgets/people/expandable_text.dart';
import '../widgets/people/info_pill.dart';
import '../utils/fuzzy_date.dart' show fuzzyDateLabel;
import '../widgets/people/people_labels.dart';
import '../widgets/people/people_routes.dart';
import '../widgets/people/person_card.dart';

class CharacterScreen extends StatefulWidget {
  final int characterId;
  final String? name;
  final String? imageUrl;

  /// Replaces the AniList API, for tests.
  final PeopleApi? api;

  /// Replaces the AniList client that toggles the favourite, for tests.
  final AniListService? service;

  const CharacterScreen({
    super.key,
    required this.characterId,
    this.name,
    this.imageUrl,
    this.api,
    this.service,
  });

  @override
  State<CharacterScreen> createState() => _CharacterScreenState();
}

class _CharacterScreenState extends State<CharacterScreen> {
  late final AniListService _service = widget.service ?? AniListService();
  late final PeopleApi _api = widget.api ?? PeopleApi();
  CharacterDetail? _data;
  bool _loading = true;
  // ToggleFavourite flips whatever AniList has, so the button waits for a
  // fresh copy instead of trusting a possibly stale cached isFavourite.
  bool _isFresh = false;
  // A second toggle sent before the first returns would flip it back.
  bool _togglingFav = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static CharacterDetail _decode(Object? json) =>
      CharacterDetail.fromJson(json) ?? (throw const FormatException('Not a cached character'));

  Future<void> _load({bool force = false}) async {
    final auth = context.read<AuthService>();
    final token = auth.token;
    final viewerId = auth.user?['id'] as int?;
    final id = widget.characterId;
    // The response carries the viewer's own isFavourite.
    final key = switch ((token, viewerId)) {
      (null, _) => 'anon:character:$id',
      (_, final int viewer) => ApiCache.userKey(viewer, 'character:$id'),
      _ => null, // Account id not fetched yet: no cache namespace for it.
    };
    final cache = context.read<ApiCache>();

    void show(CharacterDetail data, {required bool isFresh}) {
      if (!mounted) return;
      setState(() {
        _data = data;
        _isFresh = isFresh;
        _loading = false;
      });
    }

    try {
      if (key == null) {
        show(await _api.getCharacter(id, token: token), isFresh: true);
        return;
      }
      await cache.load<CharacterDetail>(
        key: key,
        fetch: () => _api.getCharacter(id, token: token),
        decode: _decode,
        onData: show,
        force: force,
      );
    } on Exception catch (e) {
      debugPrint('[CharacterScreen] Loading character $id failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _retry() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _toggleFavourite() async {
    if (_togglingFav) return;
    final auth = context.read<AuthService>();
    final token = auth.token;
    if (!auth.isLoggedIn || token == null) return;
    final lang = context.read<SettingsProvider>().language;
    final messenger = ScaffoldMessenger.of(context);
    final wasFav = _data?.isFavourite == true;
    setState(() => _togglingFav = true);
    var ok = false;
    try {
      ok = await _service.toggleCharacterFavourite(
          characterId: widget.characterId, token: token);
    } on Exception catch (e) {
      debugPrint('[CharacterScreen] Toggling favourite failed: $e');
    }
    if (!mounted) return;
    setState(() => _togglingFav = false);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(tr('save_failed', lang))));
      return;
    }
    final current = _data;
    if (current != null) {
      if (!wasFav) lightHaptic();
      setState(() => _data = current.copyWith(isFavourite: !wasFav));
    }
    _load(force: true);
    profileRefreshNotifier.value++;
  }

  @override
  Widget build(BuildContext context) {
    final isFav = _data?.isFavourite == true;
    final lang = context.watch<SettingsProvider>().language;
    return Scaffold(
      body: Stack(
        children: [
          FadeSwitcher(child: _loading ? _buildPlaceholder() : _buildContent()),
          // 44px touch targets around 36px circles, so offsets are 4px smaller.
          Positioned(
            top: MediaQuery.of(context).padding.top + 2,
            left: 8,
            right: 8,
            // The buttons' blurs read the photo once, together.
            child: BackdropGroup(
              child: Row(
                children: [
                  overlayBtn(
                    icon: Icons.arrow_back,
                    tooltip: tr('tooltip_back', lang),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  // Pops when it becomes a favourite, not when it stops.
                  PopOnChange(
                    value: isFav,
                    when: (value) => value == true,
                    child: overlayBtn(
                      icon: isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.red : Colors.white,
                      tooltip: tr('tooltip_favourite', lang),
                      onPressed: _isFresh && !_togglingFav ? _toggleFavourite : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shaped like the loaded page (the photo with the name over its bottom,
  /// then the info pills), so cross-fading to it doesn't jump.
  Widget _buildPlaceholder() {
    final topPadding = MediaQuery.of(context).padding.top;
    final cs = Theme.of(context).colorScheme;
    Widget block(double width, double height, {double radius = 6, Color? color}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color ?? cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(radius),
          ),
        );
    final onPhoto = cs.surface.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: _photoHeight + topPadding,
          padding: const EdgeInsets.only(bottom: 24),
          alignment: Alignment.bottomCenter,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              block(180, 24, color: onPhoto),
              const SizedBox(height: 8),
              block(110, 14, color: onPhoto),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [block(84, 26, radius: 20), block(64, 26, radius: 20), block(96, 26, radius: 20)],
          ),
        ),
      ],
    );
  }

  /// Height of the photo at the top, under the status bar.
  static const _photoHeight = 340.0;

  Widget _buildContent() {
    final d = _data;
    if (d == null) return _buildError();

    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final image = d.imageUrl ?? widget.imageUrl;
    final name = d.name.isNotEmpty ? d.name : widget.name ?? '';
    final nativeName = d.nativeName;
    final description = cleanReviewText(d.description, spoilerPlaceholder: tr('review_spoiler', lang));
    final rawGender = d.gender;
    final gender = rawGender != null ? genderLabel(rawGender, lang) : null;
    final age = d.age;
    final bloodType = d.bloodType;
    // Characters' birth years are often fictional, so only the day is shown.
    final dobStr = fuzzyDateLabel(d.dateOfBirth, lang, withYear: false);
    final media = d.media;
    // Japanese first, then whoever dubs in the viewer's language.
    final voiceActors = sortVoiceActors(d.voiceActors, preferredLanguage: lang);

    final surface = Theme.of(context).colorScheme.surface;
    final topPadding = MediaQuery.of(context).padding.top;
    final cs = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        // ── Hero image card ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              color: surface,
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
              alignment: Alignment.bottomCenter,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  child: SizedBox(
                    height: _photoHeight + topPadding,
                    width: double.infinity,
                    child: image != null
                        ? CachedNetworkImage(
                            imageUrl: image,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            memCacheWidth: 600,
                            placeholder: (ctx, _) => Container(color: cs.surfaceContainerHighest),
                            errorWidget: (_, _, _) => Container(color: cs.surfaceContainerHighest),
                          )
                        : Container(color: cs.surfaceContainerHighest),
                  ),
                ),
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, surface.withValues(alpha: 0.5), surface],
                          stops: const [0.45, 0.75, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      if (nativeName != null) ...[
                        const SizedBox(height: 4),
                        Text(nativeName,
                            style: TextStyle(
                                fontSize: 14,
                                color: cs.onSurface.withValues(alpha: 0.55))),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Info pills ───────────────────────────────────────────────────
        if (gender != null || age != null || bloodType != null || dobStr != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (gender != null) InfoPill(icon: Icons.person_outline_rounded, label: gender),
                  if (age != null) InfoPill(icon: Icons.cake_outlined, label: age),
                  if (bloodType != null) InfoPill(icon: Icons.water_drop_outlined, label: bloodType),
                  if (dobStr != null) InfoPill(icon: Icons.calendar_today_outlined, label: dobStr),
                ],
              ),
            ),
          ),

        // ── Description ──────────────────────────────────────────────────
        if (description.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(tr('char_about', lang)),
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

        // ── Voice actors ─────────────────────────────────────────────────
        if (voiceActors.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
              child: _sectionLabel(tr('staff_voice_actors', lang).toUpperCase()),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: PersonCard.rowHeight(),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: voiceActors.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (_, i) {
                  final actor = voiceActors[i];
                  return PersonCard(
                    name: actor.name,
                    imageUrl: actor.imageUrl,
                    subtitle: voiceLanguageLabel(actor.language, lang),
                    onTap: () => openStaff(context, actor),
                  );
                },
              ),
            ),
          ),
        ],

        // ── Appears in ───────────────────────────────────────────────────
        if (media.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
              child: _sectionLabel(tr('char_appears_in', lang)),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 165,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: media.length,
                itemBuilder: (_, i) => _mediaCard(media[i], settings.resolveTitle(media[i].title), i),
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildError() {
    final lang = context.watch<SettingsProvider>().language;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(tr('load_error', lang),
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: Text(tr('retry', lang)),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 0.7),
        ),
      );

  /// [title] is in the viewer's title language; [index] is its place in the
  /// row (AniList may list a media twice, and hero tags must differ).
  Widget _mediaCard(MediaRef media, String title, int index) {
    final image = media.coverUrl;
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    final heroTag = coverHeroTag('character-${widget.characterId}-media-$index', media.id);

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: MergeSemantics(
        child: Semantics(
          button: true,
          child: Pressable(
            onTap: () => openMedia(context, media, heroTag: heroTag),
            child: SizedBox(
              width: 100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    height: 130,
                    child: RoundedHero(
                      tag: heroTag,
                      child: image != null
                          ? CachedNetworkImage(
                              imageUrl: image,
                              fit: BoxFit.cover,
                              memCacheWidth: 200,
                              fadeInDuration: AppMotion.of(context, AppMotion.short),
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, _) => placeholder,
                              errorWidget: (_, _, _) => placeholder,
                            )
                          : placeholder,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
