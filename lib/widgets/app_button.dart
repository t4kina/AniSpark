import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_motion.dart';
import '../theme/app_text.dart';
import 'motion/pressable.dart';

/// What an [AppButton] is drawn with.
enum AppButtonKind {
  /// Filled with the accent: the one thing a screen asks for.
  primary,

  /// A quiet grey fill, for a second choice next to a primary one.
  tonal,

  /// Translucent white, for buttons drawn over a cover or a blurred backdrop.
  glass,

  /// Filled with the danger colour: confirms something that cannot be undone.
  danger,
}

/// The app's labelled button. It shrinks under the finger and springs back
/// (see `Pressable`), and while [busy] its label gives way to a spinner
/// without the button changing size, so the wait is shown where the finger
/// was and not somewhere else on the screen.
///
/// A null [onPressed] disables it; while [busy] it ignores taps.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = AppButtonKind.primary,
    this.large = false,
    this.expand = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonKind kind;

  /// The taller size, for the main action at the bottom of a sheet or page.
  final bool large;

  /// Fills the width it is given instead of hugging its label.
  final bool expand;

  /// Shows a spinner in place of the label and ignores taps.
  final bool busy;

  static const _height = 44.0;
  static const _largeHeight = 52.0;
  static const _disabledOpacity = 0.45;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color background, Color foreground, BoxBorder? border) = switch (kind) {
      AppButtonKind.primary => (cs.primary, cs.onPrimary, null),
      AppButtonKind.tonal => (cs.surfaceContainerHighest, cs.onSurface, null),
      AppButtonKind.danger => (context.colors.danger, Colors.white, null),
      AppButtonKind.glass => (
          Colors.white.withValues(alpha: 0.12),
          Colors.white,
          Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
    };
    final enabled = onPressed != null;
    final duration = AppMotion.of(context, AppMotion.short);
    final textStyle = large ? AppText.headline.copyWith(fontWeight: FontWeight.w600) : AppText.subhead;
    final icon = this.icon;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: large ? 20 : 18, color: foreground),
          const SizedBox(width: AppSpace.sm),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle.copyWith(color: foreground),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled && !busy,
      // Ignoring taps, rather than dropping the callback, keeps the button's
      // subtree in place so the label and the spinner can cross-fade.
      child: IgnorePointer(
        ignoring: !enabled || busy,
        child: Pressable(
          onTap: onPressed ?? () {},
          child: AnimatedOpacity(
            opacity: enabled ? 1 : _disabledOpacity,
            duration: duration,
            child: Container(
              width: expand ? double.infinity : null,
              constraints: BoxConstraints(minHeight: large ? _largeHeight : _height),
              padding: EdgeInsets.symmetric(horizontal: large ? AppSpace.xl : AppSpace.lg, vertical: AppSpace.sm),
              decoration: BoxDecoration(color: background, borderRadius: AppRadius.mdAll, border: border),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(opacity: busy ? 0 : 1, duration: duration, child: content),
                  AnimatedSwitcher(
                    duration: duration,
                    child: busy
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
