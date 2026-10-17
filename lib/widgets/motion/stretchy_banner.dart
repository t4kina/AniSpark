import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// A page's header image that feels attached to the page:
///
/// * pulled down (iOS bounce), it zooms from its bottom edge to fill the gap
///   above instead of leaving an empty band;
/// * scrolled, it drifts at [parallax] speed for a little depth (not when
///   the system asks to reduce motion; the stretch is kept, as it follows
///   the finger);
/// * a soft dark scrim at the top keeps the status bar and the page's
///   buttons readable over light images.
///
/// [controller] is the page's scroll controller. Place the banner at the top
/// of the scroll view, sized by its parent; ancestors must not clip above
/// it. While scrolling only a transform changes and the image isn't
/// repainted.
class StretchyBanner extends StatelessWidget {
  const StretchyBanner({super.key, required this.controller, required this.child, this.parallax = 0.5});

  final ScrollController controller;

  /// The image, filling the banner.
  final Widget child;

  /// How far the image lags behind the scroll (0 = scrolls with the page).
  final double parallax;

  /// The scrim covers the status bar plus the page's top buttons.
  static const _scrimBelowStatusBar = 72.0;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final scrimHeight = MediaQuery.paddingOf(context).top + _scrimBelowStatusBar;
    final content = RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: scrimHeight,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x73000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return ClipRect(
          // Only the bottom edge clips, so the stretched image can grow up
          // into the overscroll gap while the drifting one never covers
          // the content below.
          clipper: const _ClipBelow(),
          child: AnimatedBuilder(
            animation: controller,
            child: content,
            builder: (context, content) {
              final offset = _offset();
              if (offset < 0 && height > 0) {
                return Transform.scale(
                  scale: 1 + -offset / height,
                  alignment: Alignment.bottomCenter,
                  child: content,
                );
              }
              if (offset > 0 && !reduced && offset < height * 2) {
                return Transform.translate(offset: Offset(0, offset * parallax), child: content);
              }
              return content!;
            },
          ),
        );
      },
    );
  }

  double _offset() {
    final positions = controller.positions;
    return positions.isEmpty ? 0 : positions.last.pixels;
  }
}

class _ClipBelow extends CustomClipper<Rect> {
  const _ClipBelow();

  static const _unbounded = 100000.0;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-_unbounded, -_unbounded, size.width + _unbounded, size.height);

  @override
  bool shouldReclip(_ClipBelow oldClipper) => false;
}
