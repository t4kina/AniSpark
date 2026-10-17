import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Round frosted-glass icon button drawn over banners and covers.
///
/// The visible circle is 36px, inside a 44px touch target, and [tooltip]
/// doubles as the label read by screen readers. Buttons placed side by side
/// should share a [BackdropGroup], so their blurs read the banner once.
///
/// No press animation of its own: callers such as the favourite hearts wrap
/// it in their own pop, which a second scale would fight.
Widget overlayBtn({
  required IconData icon,
  Color color = Colors.white,
  required VoidCallback? onPressed,
  String? tooltip,
}) {
  final button = Semantics(
    button: true,
    enabled: onPressed != null,
    label: tooltip,
    child: GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: ClipOval(
            child: BackdropFilter.grouped(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tooltip == null ? button : Tooltip(message: tooltip, child: button);
}
