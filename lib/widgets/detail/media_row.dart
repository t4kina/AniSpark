import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../motion/cover_hero.dart';
import '../motion/pressable.dart';
import '../motion/rounded_hero.dart';

/// A media in a [DetailMediaRow].
class DetailMediaItem {
  const DetailMediaItem({required this.id, required this.title, required this.subtitle, this.coverUrl});

  /// Null for a malformed entry, which is shown but can't be opened.
  final int? id;
  final String title;
  final String? coverUrl;

  /// The grey line under the title (the relation, the recommendation's
  /// likes…).
  final Widget subtitle;
}

/// A horizontal row of covers on the media detail page (Relations,
/// Recommended). Tapping one calls [onOpen] with the hero tag its cover
/// has, so the cover flies into the next detail page.
class DetailMediaRow extends StatelessWidget {
  const DetailMediaRow({
    super.key,
    required this.items,
    required this.heroScope,
    required this.onOpen,
    this.height = 200,
  });

  static const _coverSize = Size(110, 150);
  static const _coverRadius = BorderRadius.all(Radius.circular(8));

  final List<DetailMediaItem> items;

  /// Unique on the page; each cover's tag also gets its position, since
  /// AniList may list a media twice.
  final String heroScope;
  final void Function(DetailMediaItem item, String heroTag) onOpen;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    final fadeIn = AppMotion.of(context, AppMotion.short);
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          final id = item.id;
          final cover = item.coverUrl;
          final heroTag = id == null ? null : coverHeroTag('$heroScope-$i', id);
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Pressable(
              onTap: heroTag == null ? null : () => onOpen(item, heroTag),
              child: SizedBox(
                width: _coverSize.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox.fromSize(
                      size: _coverSize,
                      child: RoundedHero(
                        tag: heroTag,
                        borderRadius: _coverRadius,
                        child: cover == null
                            ? placeholder
                            : CachedNetworkImage(
                                imageUrl: cover,
                                fit: BoxFit.cover,
                                memCacheWidth: 220,
                                fadeInDuration: fadeIn,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, _) => placeholder,
                                errorWidget: (_, _, _) => placeholder,
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    item.subtitle,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
