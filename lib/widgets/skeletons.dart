import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmering placeholder shown in place of content that is still loading,
/// shaped like that content so the layout doesn't jump when it arrives.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[600]! : Colors.grey[100]!,
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

/// Placeholder for the anime/manga list rows (cover + title + progress).
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 8});

  final int rows;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 8),
          itemCount: rows,
          itemBuilder: (_, _) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 80, height: 115),
                SizedBox(width: 12),
                Expanded(
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
