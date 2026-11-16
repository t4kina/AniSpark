import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../screens/detail_screen.dart';
import '../theme/app_layout.dart';
import '../theme/app_text.dart';
import 'app_image.dart';
import 'blurred_backdrop.dart';
import 'genre_filter_sheet.dart' show genreLabel;
import 'media_preview.dart';
import 'motion/cover_hero.dart';
import 'motion/pressable.dart';
import 'motion/rounded_hero.dart';

/// The one title Discover leads with: what is trending most right now, on
/// its own banner, with its cover, score and genres. A tap opens it; holding
/// it previews it.
///
/// Without a banner the cover stands in, blurred, so the card is never an
/// empty box.
class HomeSpotlight extends StatelessWidget {
  const HomeSpotlight({super.key, required this.media});

  /// An AniList `Media` map, as the trending row has it.
  final Map<String, dynamic> media;

  static const height = 176.0;
  static const coverSize = Size(68, 96);
  static const _heroScope = 'home-spotlight';
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
    final heroTag = id == null ? null : coverHeroTag(_heroScope, id);
    final facts = [
      if (score is num) '★ ${(score / 10).toStringAsFixed(1)}',
      for (final genre in (media['genres'] as List? ?? const []).take(_genresShown))
        if (genre is String) genreLabel(genre, lang),
    ].join(' · ');

    final Widget backdrop;
    if (banner != null && banner.isNotEmpty) {
      backdrop = AppImage(url: banner, cacheWidth: 800, fill: false);
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
                  MaterialPageRoute<void>(
                    builder: (_) => DetailScreen(animeId: id, heroTag: heroTag, initialCoverUrl: cover),
                  ),
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
                // Keeps the white text readable on any banner.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x33000000), Color(0xCC000000)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox.fromSize(
                        size: coverSize,
                        child: RoundedHero(tag: heroTag, child: AppImage(url: cover, cacheWidth: 240)),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: cs.primary, borderRadius: AppRadius.pillAll),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.trending_up_rounded, size: 13, color: cs.onPrimary),
                                  const SizedBox(width: 3),
                                  Text(
                                    '#1',
                                    style: AppText.micro.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.headline.copyWith(color: Colors.white, height: 1.2),
                            ),
                            if (facts.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                facts,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                              ),
                            ],
                          ],
                        ),
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
