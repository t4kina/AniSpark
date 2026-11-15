import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_motion.dart';

/// Shimmering placeholder shown in place of content that is still loading,
/// shaped like that content so the layout doesn't jump when it arrives.
///
/// Its blocks are the colour images load over, so a cover arriving in a
/// block changes nothing around it, and they hold still when motion is
/// reduced.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  /// How far the passing band is lifted toward white.
  static const _darkLift = 0.1;
  static const _lightLift = 0.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    final lift = theme.brightness == Brightness.dark ? _darkLift : _lightLift;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: Color.lerp(base, Colors.white, lift)!,
      enabled: !AppMotion.reduced(context),
      child: child,
    );
  }
}

/// A solid block inside a [Skeleton].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Placeholder for rows of a cover beside a title and two details: the
/// anime/manga lists, with [coverSize] for lists of smaller covers.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 8, this.coverSize = const Size(80, 115)});

  final int rows;
  final Size coverSize;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 8),
          itemCount: rows,
          itemBuilder: (_, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: coverSize.width, height: coverSize.height),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 4),
                      SkeletonBox(height: 14),
                      SizedBox(height: 8),
                      SkeletonBox(width: 140, height: 12),
                      SizedBox(height: 8),
                      SkeletonBox(width: 60, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Placeholder for activity feed cards (avatar + two lines + cover).
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key, this.cards = 6});

  final int cards;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: cards,
          itemBuilder: (_, _) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 36, height: 36, radius: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 180, height: 12),
                      SizedBox(height: 8),
                      SkeletonBox(height: 14),
                      SizedBox(height: 8),
                      SkeletonBox(width: 70, height: 10),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                SkeletonBox(width: 45, height: 64),
              ],
            ),
          ),
        ),
      );
}

/// Placeholder for the media detail page's title, studio and stats, under
/// the cover. The page draws the banner and the cover itself while loading
/// (the cover flies in from the list that opened it).
class DetailInfoSkeleton extends StatelessWidget {
  const DetailInfoSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(
          children: [
            const SkeletonBox(width: 220, height: 22),
            const SizedBox(height: 10),
            const SkeletonBox(width: 120, height: 14),
            const SizedBox(height: 20),
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  const Expanded(
                    child: Column(
                      children: [
                        SkeletonBox(width: 64, height: 9),
                        SizedBox(height: 6),
                        SkeletonBox(width: 44, height: 22),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
}

/// Placeholder for the media detail page under its header: the list
/// buttons and the start of the summary.
class DetailBodySkeleton extends StatelessWidget {
  const DetailBodySkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    const Expanded(child: SkeletonBox(height: 66, radius: 10)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 36),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 70, height: 11)),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonBox(width: i == 3 ? 180 : null, height: 12),
                ),
              ),
          ],
        ),
      );
}

/// Placeholder for a grid of covers with a title and a detail under each.
/// [shrinkWrap] makes it as tall as its rows, for a grid inside a page
/// that scrolls.
class GridSkeleton extends StatelessWidget {
  const GridSkeleton({
    super.key,
    required this.gridDelegate,
    this.padding = const EdgeInsets.all(12),
    this.count = 12,
    this.shrinkWrap = false,
  });

  final SliverGridDelegate gridDelegate;
  final EdgeInsets padding;
  final int count;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: GridView.builder(
          shrinkWrap: shrinkWrap,
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          gridDelegate: gridDelegate,
          itemCount: count,
          itemBuilder: (_, _) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SkeletonBox(height: double.infinity, radius: 8)),
              SizedBox(height: 5),
              SkeletonBox(height: 12),
              SizedBox(height: 4),
              SkeletonBox(width: 60, height: 10),
            ],
          ),
        ),
      );
}

/// Placeholder for a few people: an avatar beside a name and, with two
/// [lines], what they wrote. Only as tall as its rows, for sheets and
/// sections that grow with their content.
class PeopleSkeleton extends StatelessWidget {
  const PeopleSkeleton({
    super.key,
    this.rows = 3,
    required this.avatarSize,
    this.lines = 1,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  }) : assert(lines == 1 || lines == 2);

  final int rows;
  final double avatarSize;
  final int lines;

  /// Around each row.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: padding,
                child: Row(
                  children: [
                    SkeletonBox(width: avatarSize, height: avatarSize, radius: avatarSize / 2),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SkeletonBox(width: 130, height: 12),
                          if (lines > 1) ...[
                            const SizedBox(height: 6),
                            const SkeletonBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// Placeholder for a profile page: its card, then the start of what is
/// under it. [topGap] is the room the page leaves above the card.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key, this.topGap = 8});

  final double topGap;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + topGap, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(height: 320, radius: 32),
              const SizedBox(height: 28),
              const SkeletonBox(width: 120, height: 16),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    const Expanded(child: SkeletonBox(height: 150, radius: 8)),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
}
