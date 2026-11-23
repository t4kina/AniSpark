import 'package:flutter/material.dart';

import '../../theme/app_layout.dart';
import '../../theme/app_motion.dart';
import '../motion/fade_switcher.dart';
import '../motion/pop_on_change.dart';
import '../motion/pressable.dart';

/// One of the detail page's buttons about the viewer's own list entry: an
/// [icon], what it says now ([label]) and what it is ([sublabel]).
///
/// [highlighted] marks it as holding something of theirs (the series is in
/// their list). When that becomes true the button turns into a chip of the
/// accent colour: the fill and the edge glide over, the new label and icon
/// fade in over the old ones and the icon pops. Going back is as smooth,
/// without the pop.
class ListActionButton extends StatelessWidget {
  const ListActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;
  final bool highlighted;

  static const _iconSize = 15.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final neutral = cs.surfaceContainerHighest;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.medium),
        curve: AppMotion.standard,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: AppSpace.sm),
        decoration: BoxDecoration(
          color: highlighted ? Color.alphaBlend(cs.primary.withValues(alpha: 0.16), neutral) : neutral,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: highlighted ? cs.primary.withValues(alpha: 0.7) : cs.outline.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopOnChange(
              value: highlighted,
              when: (value) => value == true,
              child: SizedBox.square(
                dimension: _iconSize,
                child: FadeSwitcher(
                  duration: AppMotion.short,
                  child: Icon(icon, key: ValueKey(icon), size: _iconSize, color: cs.primary),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            FadeSwitcher(
              duration: AppMotion.short,
              child: Text(
                label,
                key: ValueKey(label),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onSurface),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.45), letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
