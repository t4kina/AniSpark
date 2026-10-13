import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../theme/app_motion.dart';
import '../utils/translations.dart' show tr;

/// AniList genre names (sent to the API as is) and their display keys,
/// offered as filters by search and the Discover grids.
const genreLabelKeys = {
  'Action': 'search_genre_action',
  'Adventure': 'search_genre_adventure',
  'Comedy': 'search_genre_comedy',
  'Drama': 'search_genre_drama',
  'Ecchi': 'search_genre_ecchi',
  'Fantasy': 'search_genre_fantasy',
  'Horror': 'search_genre_horror',
  'Mahou Shoujo': 'search_genre_mahou_shoujo',
  'Mecha': 'search_genre_mecha',
  'Music': 'search_genre_music',
  'Mystery': 'search_genre_mystery',
  'Psychological': 'search_genre_psychological',
  'Romance': 'search_genre_romance',
  'Sci-Fi': 'search_genre_sci_fi',
  'Slice of Life': 'search_genre_slice_of_life',
  'Sports': 'search_genre_sports',
  'Supernatural': 'search_genre_supernatural',
  'Thriller': 'search_genre_thriller',
};

/// Translated name of an AniList [genre]; unknown genres are shown as is.
String genreLabel(String genre, String lang) {
  final key = genreLabelKeys[genre];
  return key == null ? genre : tr(key, lang);
}

/// A rounded filter option that shows a check while [selected]. The pill is
/// compact, but its tap area is [minTapHeight] tall.
class FilterOptionChip extends StatelessWidget {
  const FilterOptionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor,
  });

  static const minTapHeight = 44.0;

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Colour of a selected chip; the theme's accent by default.
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selectedColor ?? cs.primary;
    final duration = AppMotion.of(context, AppMotion.short);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTapHeight),
          child: Align(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: duration,
              curve: AppMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.2) : cs.surfaceContainerHighest,
                border: Border.all(color: selected ? color : Colors.transparent),
                borderRadius: BorderRadius.circular(20),
              ),
              // The check grows in instead of pushing the label aside at once.
              child: AnimatedSize(
                duration: duration,
                curve: AppMotion.standard,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected) ...[
                      Icon(Icons.check, size: 14, color: color),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected ? color : null,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every genre of [genreLabelKeys] as a [FilterOptionChip], [selected] ones
/// checked; tapping one calls [onToggle] with its AniList name.
class GenreChips extends StatelessWidget {
  const GenreChips({super.key, required this.selected, required this.onToggle, this.selectedColor});

  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final lang = context.select<SettingsProvider, String>((s) => s.language);
    return Wrap(
      spacing: 8,
      children: [
        for (final genre in genreLabelKeys.keys)
          FilterOptionChip(
            label: genreLabel(genre, lang),
            selected: selected.contains(genre),
            selectedColor: selectedColor,
            onTap: () => onToggle(genre),
          ),
      ],
    );
  }
}

/// Search's filters sheet: pick genres, then close it to apply them through
/// [onApply] (Reset unticks them all first).
class GenreFilterSheet extends StatefulWidget {
  const GenreFilterSheet({super.key, required this.selected, required this.onApply, this.selectedColor});

  final Set<String> selected;
  final void Function(Set<String>) onApply;
  final Color? selectedColor;

  @override
  State<GenreFilterSheet> createState() => _GenreFilterSheetState();
}

class _GenreFilterSheetState extends State<GenreFilterSheet> {
  late Set<String> _draft = Set<String>.from(widget.selected);

  void _close() {
    Navigator.pop(context);
    widget.onApply(_draft);
  }

  void _toggle(String genre) => setState(() {
        _draft = _draft.contains(genre) ? _draft.difference({genre}) : {..._draft, genre};
      });

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _draft = {}),
                  child: Text(tr('search_reset', lang),
                      style: const TextStyle(color: Colors.grey)),
                ),
                Expanded(
                  child: Center(
                    child: Text(tr('filters', lang),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _close,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Text(
                  tr('genre', lang).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                GenreChips(selected: _draft, onToggle: _toggle, selectedColor: widget.selectedColor),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
