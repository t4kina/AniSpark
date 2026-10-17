import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/media_extras_api.dart';
import '../../utils/translations.dart';
import '../motion/pressable.dart';
import '../skeletons.dart';
import '../user_avatar.dart';

const _avatarSize = 48.0;
const _avatarRadius = 8.0;
const _avatarGap = 4.0;
const _bubbleRadius = 20.0;
const _bubblePadding = 16.0;

/// A review drawn as the reviewer's avatar with their summary in a speech
/// bubble that floats on a soft shadow. Tapping it calls [onTap].
class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.review,
    required this.onTap,
    this.width,
    this.maxLines = 3,
  });

  final Review review;
  final VoidCallback onTap;

  /// Fixed width for horizontal rows; fills the available width when null.
  final double? width;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lang = context.watch<SettingsProvider>().language;
    final isDark = theme.brightness == Brightness.dark;
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: trf('review_by', lang, {'name': review.user.name}),
        child: Pressable(
          // A wide card only needs a hint of a press.
          pressedScale: 0.98,
          onTap: onTap,
          child: SizedBox(
            width: width,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(url: review.user.avatarUrl, size: _avatarSize, radius: _avatarRadius),
                const SizedBox(width: _avatarGap),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(_bubblePadding, _bubblePadding, _bubblePadding, 12),
                    decoration: ShapeDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.92),
                      shape: const SpeechBubbleBorder(),
                      shadows: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.10),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          review.summary,
                          maxLines: maxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            fontStyle: FontStyle.italic,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ReviewUpvotes(count: review.rating),
                        ),
                      ],
                    ),
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

/// Thumbs-up icon with how many users liked a review.
class ReviewUpvotes extends StatelessWidget {
  const ReviewUpvotes({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Semantics(
      label: trf('review_upvotes', lang, {'n': count}),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.thumb_up_alt_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 4),
          Text('$count', style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
    );
  }
}

/// Loading placeholder shaped like a [ReviewCard]; place inside a [Skeleton].
class ReviewCardSkeleton extends StatelessWidget {
  const ReviewCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: _avatarSize, height: _avatarSize, radius: _avatarRadius),
          SizedBox(width: _avatarGap + SpeechBubbleBorder.defaultTailWidth),
          Expanded(child: SkeletonBox(height: 110, radius: _bubbleRadius)),
        ],
      );
}

/// A rounded rectangle with a small triangular tail on its left edge,
/// pointing at whatever sits to the left (the reviewer's avatar).
///
/// The tail takes [tailWidth] on the left, which [dimensions] reports so
/// a decorated `Container`'s padding starts inside the bubble.
class SpeechBubbleBorder extends ShapeBorder {
  const SpeechBubbleBorder({
    this.radius = _bubbleRadius,
    this.tailWidth = defaultTailWidth,
    this.tailHeight = 14,
    this.tailTop = 16,
  });

  static const defaultTailWidth = 8.0;

  final double radius;
  final double tailWidth;
  final double tailHeight;

  /// Distance from the top of the bubble to the top of the tail.
  final double tailTop;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(left: tailWidth);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Rect.fromLTRB(rect.left + tailWidth, rect.top, rect.right, rect.bottom);
    final tailStart = body.top + tailTop;
    final bubble = Path()..addRRect(RRect.fromRectAndRadius(body, Radius.circular(radius)));
    // The tail's base reaches into the bubble so the union has no seam.
    final tail = Path()
      ..moveTo(body.left + tailWidth, tailStart)
      ..lineTo(rect.left, tailStart + tailHeight / 2)
      ..lineTo(body.left + tailWidth, tailStart + tailHeight)
      ..close();
    return Path.combine(PathOperation.union, bubble, tail);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => SpeechBubbleBorder(
        radius: radius * t,
        tailWidth: tailWidth * t,
        tailHeight: tailHeight * t,
        tailTop: tailTop * t,
      );
}
