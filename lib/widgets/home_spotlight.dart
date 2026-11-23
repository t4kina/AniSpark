import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../screens/detail_screen.dart';
import '../theme/app_layout.dart';
import '../theme/app_text.dart';
import 'app_image.dart';
import 'blurred_backdrop.dart';
import '../utils/translations.dart' show tr;
import 'genre_filter_sheet.dart' show genreLabel;
import 'media_preview.dart';
import 'motion/pressable.dart';

/// The one title Discover leads with: what is trending most right now, its
/// banner filling the whole box, with its title large over it, its score and
/// genres, and a button to open it. A tap anywhere opens it; holding it
/// previews it.
///
/// Without a banner the cover stands in, blurred, so the box is never empty.
class HomeSpotlight extends StatelessWidget {
  const HomeSpotlight({super.key, required this.media});

  /// An AniList `Media` map, as the trending row has it.
  final Map<String, dynamic> media;

  static const height = 252.0;
  static const _genresShown = 2;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final id = media['id'] as int?;
    final title = settings.resolveTitle(media['title'] as Map<String, dynamic>?);
    final cover = (media['coverImage'] as Map?)?['large'] as String?;
    final banner = media['bannerImage'] as String?;
    final score = media['averageScore'];
    final facts = [
      if (score is num) '★ ${(score / 10).toStringAsFixed(1)}',
      for (final genre in (media['genres'] as List? ?? const []).take(_genresShown))
        if (genre is String) genreLabel(genre, lang),
    ].join(' · ');

    final Widget backdrop;
    if (banner != null && banner.isNotEmpty) {
      backdrop = AppImage(url: banner, cacheWidth: 1080, fill: false);
    } else if (cover != null && cover.isNotEmpty) {
      backdrop = BlurredBackdrop(url: cover, decodeWidth: 240);
    } else {
      backdrop = ColoredBox(color: cs.primary.withValues(alpha: 0.35));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, 0),
      child: Pressable(
        pressedScale: 0.98,
        onTap: id == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => DetailScreen(animeId: id, initialCoverUrl: cover)),
                ),
        onLongPress: id == null ? null : () => showMediaPreview(context, media: media),
        child: ClipRRect(
          borderRadius: AppRadius.lgAll,
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                backdrop,
                // Clear at the top, dark under the title so it always reads.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.3, 1],
                      colors: [Color(0x00000000), Color(0xD9000000)],
                    ),
                  ),
                ),
                Positioned(left: AppSpace.lg, top: AppSpace.md, child: _TrendingPill(lang: lang)),
                Positioned(
                  left: AppSpace.lg,
                  right: AppSpace.lg,
                  bottom: AppSpace.lg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title.copyWith(color: Colors.white, fontSize: 24, height: 1.15),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              facts,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.footnote.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                            ),
                          ),
                          if (id != null) ...[
                            const SizedBox(width: AppSpace.sm),
                            _OpenPill(lang: lang),
                          ],
                        ],
                      ),
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

/// "#1 trending", in the accent colour, at the top of the box.
class _TrendingPill extends StatelessWidget {
  const _TrendingPill({required this.lang});

  final String lang;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = AppText.micro.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w800);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: cs.primary, borderRadius: AppRadius.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_up_rounded, size: 14, color: cs.onPrimary),
          const SizedBox(width: 4),
          Text('#1', style: style),
          const SizedBox(width: 4),
          Text(tr('spotlight_trending', lang), style: style),
        ],
      ),
    );
  }
}

/// Says the box opens the title; the whole box is what is tapped.
class _OpenPill extends StatelessWidget {
  const _OpenPill({required this.lang});

  final String lang;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: AppRadius.pillAll),
          child: Text(
            tr('preview_open', lang),
            style: AppText.footnote.copyWith(color: Colors.black, fontWeight: FontWeight.w700),
          ),
        ),
      );
}
