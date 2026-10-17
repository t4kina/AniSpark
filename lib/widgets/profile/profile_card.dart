import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../utils/score_utils.dart';
import '../../utils/translations.dart' show tr, trf;
import '../blurred_backdrop.dart';
import '../genre_filter_sheet.dart' show genreLabel;
import '../motion/fade_switcher.dart';
import '../motion/pressable.dart';
import 'count_up_text.dart';

/// The top of a profile, own or a friend's: one card on the person's banner
/// (their blurred avatar without one) holding who they are and a glass
/// strip of their anime or manga stats, with the profile's main actions at
/// the bottom.
class ProfileCard extends StatefulWidget {
  const ProfileCard({
    super.key,
    required this.name,
    required this.lang,
    this.avatarUrl,
    this.bannerUrl,
    this.animeStats,
    this.mangaStats,
    this.scoreFormat,
    this.nameTag,
    this.cornerButton,
    this.topGap = 8,
    this.actions = const [],
    this.onCountTap,
  });

  final String name;
  final String lang;
  final String? avatarUrl;
  final String? bannerUrl;

  /// AniList `statistics.anime` / `statistics.manga` (scores on 0–100).
  final Map<String, dynamic>? animeStats;
  final Map<String, dynamic>? mangaStats;

  /// The viewer's score format, for the means.
  final String? scoreFormat;

  /// Shown beside the name, e.g. "Follows you".
  final String? nameTag;

  /// The round button at the right of the name (settings, more…): see
  /// [ProfileCard.roundButton].
  final Widget? cornerButton;

  /// Space between the status bar and the card, e.g. room for a back
  /// button above it.
  final double topGap;

  /// Full-width buttons at the bottom, side by side: see
  /// [ProfileCard.primaryButton] and [ProfileCard.secondaryButton].
  final List<Widget> actions;

  /// Tapping "N anime" / "N manga" under the name, with `ANIME` or `MANGA`.
  final ValueChanged<String>? onCountTap;

  /// A round glass button for [cornerButton].
  static Widget roundButton({required IconData icon, required String tooltip, required VoidCallback onPressed}) =>
      Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: Pressable(
            onTap: onPressed,
            child: _Glass(
              shape: const CircleBorder(),
              child: SizedBox.square(dimension: 46, child: Icon(icon, size: 20, color: Colors.white)),
            ),
          ),
        ),
      );

  /// The solid white action, for what the profile is mostly for.
  static Widget primaryButton({required String label, IconData? icon, Widget? trailing, VoidCallback? onPressed}) =>
      _ActionButton(label: label, icon: icon, trailing: trailing, onPressed: onPressed, primary: true);

  /// A glass action beside [primaryButton].
  static Widget secondaryButton({required String label, IconData? icon, Widget? trailing, VoidCallback? onPressed}) =>
      _ActionButton(label: label, icon: icon, trailing: trailing, onPressed: onPressed, primary: false);

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  bool _manga = false;

  /// The genre the person has the most anime (else manga) in.
  String? get _topGenre {
    for (final stats in [widget.animeStats, widget.mangaStats]) {
      final genres = (stats?['genres'] as List<dynamic>?)?.whereType<Map<String, dynamic>>().toList() ?? [];
      if (genres.isEmpty) continue;
      genres.sort((a, b) => ((b['count'] as num?) ?? 0).compareTo((a['count'] as num?) ?? 0));
      final genre = genres.first['genre'] as String?;
      if (genre != null && genre.isNotEmpty) return genre;
    }
    return null;
  }

  static int _int(Map<String, dynamic>? stats, String key) => (stats?[key] as num?)?.toInt() ?? 0;

  String _mean(Map<String, dynamic>? stats) {
    final mean = (stats?['meanScore'] as num?) ?? 0;
    return mean > 0 ? formatScore(mean / 10, widget.scoreFormat) : '—';
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final genre = _topGenre;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + widget.topGap, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            Positioned.fill(child: _background(context)),
            // Keeps white text readable on any banner, darker toward the
            // stats and buttons.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.25), Colors.black.withValues(alpha: 0.62)],
                  ),
                ),
              ),
            ),
            // The glass pieces blur the banner once, together.
            BackdropGroup(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.white),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _avatar(),
                          if (genre != null) ...[
                            const SizedBox(width: 14),
                            Flexible(child: _genrePill(genreLabel(genre, lang))),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _nameBlock(lang)),
                          if (widget.cornerButton != null) ...[const SizedBox(width: 12), widget.cornerButton!],
                        ],
                      ),
                      const SizedBox(height: 18),
                      Align(alignment: Alignment.centerLeft, child: _mediaToggle(lang)),
                      const SizedBox(height: 10),
                      FadeSwitcher(
                        child: KeyedSubtree(
                          key: ValueKey(_manga),
                          child: _manga ? _mangaStrip(lang) : _animeStrip(lang),
                        ),
                      ),
                      if (widget.actions.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            for (final (i, action) in widget.actions.indexed) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(child: action),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _background(BuildContext context) {
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    final banner = widget.bannerUrl;
    if (banner != null && banner.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: banner,
        fit: BoxFit.cover,
        memCacheWidth: 900,
        fadeInDuration: AppMotion.of(context, AppMotion.short),
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => _noBanner(context),
      );
    }
    return _noBanner(context);
  }

  /// Without a banner: the avatar, blurred into colour (as the app's other
  /// headers do), else the accent.
  Widget _noBanner(BuildContext context) {
    final avatar = widget.avatarUrl;
    if (avatar != null && avatar.isNotEmpty) return BlurredBackdrop(url: avatar);
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary, colors.primary.withValues(alpha: 0.35), colors.surface],
        ),
      ),
    );
  }

  Widget _avatar() {
    final avatar = widget.avatarUrl;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.35)),
      child: CircleAvatar(
        radius: 39,
        backgroundColor: Colors.black26,
        backgroundImage: avatar == null ? null : CachedNetworkImageProvider(avatar),
        child: avatar == null ? const Icon(Icons.person, size: 38, color: Colors.white70) : null,
      ),
    );
  }

  Widget _genrePill(String genre) => _Glass(
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 17, color: Color(0xFFFFD166)),
              const SizedBox(width: 7),
              Flexible(
                child: Text(trf('profile_genre_fan', widget.lang, {'genre': genre}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );

  Widget _nameBlock(String lang) {
    final anime = _int(widget.animeStats, 'count');
    final manga = _int(widget.mangaStats, 'count');
    final countStyle = TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.75));
    Widget count(String type, String text) => widget.onCountTap == null
        ? Text(text, style: countStyle)
        : Semantics(
            button: true,
            child: GestureDetector(
              onTap: () => widget.onCountTap!(type),
              behavior: HitTestBehavior.opaque,
              child: Text(text, style: countStyle),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(widget.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            if (widget.nameTag != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(widget.nameTag!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Wrap(
          children: [
            count('ANIME', trf('profile_n_anime', lang, {'n': anime})),
            Text('  ·  ', style: countStyle),
            count('MANGA', trf('profile_n_manga', lang, {'n': manga})),
          ],
        ),
      ],
    );
  }

  Widget _mediaToggle(String lang) {
    Widget option(String label, bool manga) {
      final selected = _manga == manga;
      return Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: () => setState(() => _manga = manga),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.short),
            curve: AppMotion.standard,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? const Color(0xFF17131C) : Colors.white.withValues(alpha: 0.8),
                )),
          ),
        ),
      );
    }

    return _Glass(
      shape: const StadiumBorder(),
      tint: Colors.black.withValues(alpha: 0.22),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [option(tr('nav_anime', lang), false), option(tr('nav_manga', lang), true)],
        ),
      ),
    );
  }

  // The strip's labels are one short word or two (the icons say the rest),
  // so the three stats line up.
  Widget _animeStrip(String lang) => _strip([
        _StripStat(icon: Icons.star_rounded, color: const Color(0xFFF5A524), text: _mean(widget.animeStats),
            label: tr('profile_stat_mean', lang)),
        _StripStat(icon: Icons.play_circle_fill_rounded, color: const Color(0xFF3B82F6),
            value: _int(widget.animeStats, 'episodesWatched'), label: tr('profile_episodes', lang)),
        _StripStat(icon: Icons.access_time_filled_rounded, color: const Color(0xFF8B5CF6),
            value: _int(widget.animeStats, 'minutesWatched') / 1440, fractionDigits: 1,
            label: tr('profile_stat_days', lang)),
      ]);

  Widget _mangaStrip(String lang) => _strip([
        _StripStat(icon: Icons.star_rounded, color: const Color(0xFFF5A524), text: _mean(widget.mangaStats),
            label: tr('profile_stat_mean', lang)),
        _StripStat(icon: Icons.menu_book_rounded, color: const Color(0xFF3B82F6),
            value: _int(widget.mangaStats, 'chaptersRead'), label: tr('profile_chapters', lang)),
        _StripStat(icon: Icons.library_books_rounded, color: const Color(0xFF8B5CF6),
            value: _int(widget.mangaStats, 'volumesRead'), label: tr('profile_stat_volumes', lang)),
      ]);

  Widget _strip(List<Widget> stats) => _Glass(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, stat) in stats.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: stat),
                ],
              ],
            ),
          ),
        ),
      );
}

/// A stat in the glass strip: a coloured icon beside its value and label.
/// [value] counts up the first time it shows; [text] is shown as is.
class _StripStat extends StatelessWidget {
  const _StripStat({
    required this.icon,
    required this.color,
    required this.label,
    this.value,
    this.text,
    this.fractionDigits = 0,
  });

  final IconData icon;
  final Color color;
  final String label;
  final num? value;
  final String? text;
  final int fractionDigits;

  static const _valueHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    const valueStyle = TextStyle(fontSize: 17, height: 1.2, fontWeight: FontWeight.bold, color: Colors.white);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A fixed height, so a long value that shrinks to fit doesn't
              // lift its label above the others.
              SizedBox(
                height: _valueHeight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: text != null
                      ? Text(text!, style: valueStyle)
                      : CountUpText(value!, fractionDigits: fractionDigits, style: valueStyle),
                ),
              ),
              const SizedBox(height: 2),
              // Shrinks a little on a narrow phone rather than wrap.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label,
                    maxLines: 1,
                    style: TextStyle(fontSize: 11.5, height: 1.2, color: Colors.white.withValues(alpha: 0.72))),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.primary,
    this.icon,
    this.trailing,
    this.onPressed,
  });

  final String label;
  final bool primary;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? const Color(0xFF17131C) : Colors.white;
    final content = SizedBox(
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: foreground), const SizedBox(width: 6)],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: foreground)),
          ),
          if (trailing != null) ...[const SizedBox(width: 2), trailing!],
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Pressable(
        onTap: onPressed,
        child: primary
            ? DecoratedBox(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
                child: content,
              )
            : _Glass(shape: const StadiumBorder(), child: content),
      ),
    );
  }
}

/// Frosted glass over the card's banner: blurred, lightly tinted, with a
/// thin bright rim. Shares the banner read with its siblings through the
/// card's [BackdropGroup].
class _Glass extends StatelessWidget {
  const _Glass({required this.shape, required this.child, this.tint});

  final ShapeBorder shape;
  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter.grouped(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: tint ?? Colors.white.withValues(alpha: 0.12),
            shape: switch (shape) {
              final OutlinedBorder outlined =>
                outlined.copyWith(side: BorderSide(color: Colors.white.withValues(alpha: 0.24))),
              _ => shape,
            },
          ),
          child: child,
        ),
      ),
    );
  }
}
