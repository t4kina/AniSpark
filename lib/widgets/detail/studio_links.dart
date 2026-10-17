import 'package:flutter/material.dart';

import '../../services/people_api.dart';
import '../people/people_routes.dart';

/// A media's studios as chips that open each studio's page. Studios without
/// an id (when the query didn't ask for it) are shown but can't be opened.
/// Shows nothing when there are no studios to list.
class StudioLinks extends StatelessWidget {
  const StudioLinks({
    super.key,
    required this.studios,
    this.isAnimationStudio,
    this.alignment = WrapAlignment.start,
  });

  /// The detail query's `studios { nodes { id name isAnimationStudio } }`
  /// nodes (`edges { node {…} }` work too); nameless ones are skipped.
  final List<dynamic> studios;

  /// Only animation studios when true, only the others (producers…) when
  /// false; every studio when null.
  final bool? isAnimationStudio;

  /// Where the chips sit on each line (centred under a title, for example).
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final wanted = isAnimationStudio;
    final shown = [
      for (final studio in StudioRef.listFromJson(studios))
        if (wanted == null || studio.isAnimationStudio == wanted) studio,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: alignment,
      spacing: 6,
      children: [for (final studio in shown) _StudioChip(studio: studio)],
    );
  }
}

class _StudioChip extends StatelessWidget {
  const _StudioChip({required this.studio});

  final StudioRef studio;

  @override
  Widget build(BuildContext context) {
    final id = studio.id;
    // Padded to a 48px touch target; the chip theme gives the look of the
    // detail page's other chips.
    if (id == null) {
      return Chip(
        label: Text(studio.name),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.compact,
      );
    }
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      // The name with a small chevron reads as a link, like a developer
      // link in an app store, without a generic icon.
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(studio.name),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 16, color: cs.primary.withValues(alpha: 0.7)),
        ],
      ),
      labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.compact,
      onPressed: () => openStudio(context, id, name: studio.name),
    );
  }
}
