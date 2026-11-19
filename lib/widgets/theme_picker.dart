import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_palette.dart';
import '../utils/haptics.dart';
import '../utils/translations.dart';
import 'motion/pressable.dart';

/// A row of [appThemes], each a little picture of the app in its colours
/// with its name under it. Tapping one puts it on at once.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key, required this.lang, this.inset = AppSpace.md});

  final String lang;

  /// The room at the left and right of the row, inside its block.
  final double inset;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final chosenAccent = accentColorOptions[settings.accentColorName] ?? accentColorOptions.values.first;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(inset, AppSpace.md, inset, AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, MapEntry(key: name, value: palette)) in appThemes.entries.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpace.md),
            _ThemeSwatch(
              label: tr('theme_${name.toLowerCase()}', lang),
              palette: palette,
              accent: palette.accent ?? chosenAccent,
              selected: settings.themeName == name,
              onTap: () {
                selectionHaptic();
                context.read<SettingsProvider>().setTheme(name);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.label,
    required this.palette,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final AppPalette palette;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  static const _width = 76.0;
  static const _height = 96.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: _width,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: _width,
                height: _height,
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: selected ? accent : palette.line,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Stack(
                  children: [
                    _Miniature(palette: palette, accent: accent),
                    if (selected)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.xs + 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Theme.of(context).colorScheme.onSurface : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app in a theme's colours, very small: a card with two lines of
/// text, and a button in the accent.
class _Miniature extends StatelessWidget {
  const _Miniature({required this.palette, required this.accent});

  final AppPalette palette;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, Color color) => Container(
          width: width,
          height: 5,
          decoration: BoxDecoration(color: color, borderRadius: AppRadius.pillAll),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(6)),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 18,
                decoration: BoxDecoration(color: palette.raised, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(26, palette.text),
                    const SizedBox(height: 4),
                    bar(18, palette.textTertiary),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Container(
          height: 12,
          decoration: BoxDecoration(color: accent, borderRadius: AppRadius.pillAll),
        ),
      ],
    );
  }
}
