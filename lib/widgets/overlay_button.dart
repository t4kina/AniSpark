import 'package:flutter/material.dart';

/// Round translucent icon button drawn over banners and covers.
///
/// The visible circle is 36px, inside a 44px touch target, and [tooltip]
/// doubles as the label read by screen readers.
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
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    ),
  );
  return tooltip == null ? button : Tooltip(message: tooltip, child: button);
}
