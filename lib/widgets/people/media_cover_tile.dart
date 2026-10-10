import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/people_api.dart';
import '../../utils/translations.dart';

/// Grid layout shared by the cover grids of the staff and studio pages
/// (the season browser's proportions, with room for a two-line subtitle).
const mediaCoverGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 160,
  crossAxisSpacing: 10,
  mainAxisSpacing: 14,
  childAspectRatio: 0.46,
);

/// A media cover with its score, title in the viewer's title language and a
/// grey [subtitle] (a role, the format and year…). Manga are labelled.
class MediaCoverTile extends StatelessWidget {
  const MediaCoverTile({
    super.key,
    required this.media,
    this.subtitle,
    this.subtitleLines = 1,
    this.onTap,
  });

  final MediaRef media;
  final String? subtitle;
  final int subtitleLines;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final title = settings.resolveTitle(media.title);
    final cover = media.coverUrl;
    final score = media.averageScore;
    final subtitle = this.subtitle;
    final placeholder = Container(color: Theme.of(context).colorScheme.surfaceContainerHighest);

    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (cover == null)
                        placeholder
                      else
                        CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          memCacheWidth: 240,
                          placeholder: (_, _) => placeholder,
                          errorWidget: (_, _, _) => placeholder,
                        ),
                      if (score != null && score > 0) _ScoreOverlay(score: score),
                      if (media.isManga) _CornerLabel(text: tr('nav_manga', lang)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.25),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: subtitleLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.25),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "★ 8.5" over the bottom of a cover; [score] is AniList's 0–100.
class _ScoreOverlay extends StatelessWidget {
  const _ScoreOverlay({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) => Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
            ),
          ),
          child: Text(
            '★ ${(score / 10).toStringAsFixed(1)}',
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
      );
}

/// A small dark label in the top-left corner of a cover.
class _CornerLabel extends StatelessWidget {
  const _CornerLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Positioned(
        top: 6,
        left: 6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700),
          ),
        ),
      );
}
