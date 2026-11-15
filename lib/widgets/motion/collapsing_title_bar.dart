import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_text.dart';

/// A frosted bar with the page's [title] that comes in at the top once the
/// page's own title has scrolled away under it, for pages whose header is a
/// picture with buttons floating over it and no app bar.
///
/// Nothing is drawn until the page has scrolled [revealAt]; over the next
/// [revealOver] pixels the blur and the tint build up and the title rises
/// into place, following the finger. Put it in the page's `Stack`, above the
/// scroll view and under the floating buttons; taps go through it.
///
/// [controller] is the page's scroll controller. It may be attached later
/// (e.g. once the page has loaded); the bar stays away until then.
class CollapsingTitleBar extends StatelessWidget {
  const CollapsingTitleBar({
    super.key,
    required this.controller,
    required this.title,
    required this.revealAt,
    this.revealOver = 48,
    this.sideInset = 56,
  });

  final ScrollController controller;
  final String title;
  final double revealAt;
  final double revealOver;

  /// Room at each side for the buttons floating over the bar (one by
  /// default); the title stays centred between them.
  final double sideInset;

  /// The bar's height under the status bar: that of the floating buttons'
  /// row.
  static const height = 48.0;

  static const _blur = 18.0;
  static const _tint = 0.72;
  static const _rise = 8.0;

  /// How far in the bar is (0 away, 1 fully there) at [offset].
  double _progressAt(double offset) => ((offset - revealAt) / revealOver).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: AppText.headline.copyWith(color: cs.onSurface),
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, label) {
            // One position at a time: the page swaps its placeholder for
            // its content, and both may be attached for a moment.
            final progress = controller.positions.length == 1 ? _progressAt(controller.offset) : 0.0;
            if (progress == 0) return const SizedBox.shrink();
            return ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: _blur * progress, sigmaY: _blur * progress),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: _tint * progress),
                    border: Border(
                      bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.08 * progress)),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: height,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: sideInset),
                        child: Center(
                          child: Opacity(
                            opacity: progress,
                            child: Transform.translate(offset: Offset(0, _rise * (1 - progress)), child: label),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          child: label,
        ),
      ),
    );
  }
}
