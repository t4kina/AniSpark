import 'package:flutter/material.dart';

/// A rounded grey pill with an icon and a short fact (age, birthday…).
class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.icon, required this.label, this.iconColor});

  final IconData icon;
  final String label;

  /// Defaults to a muted text colour.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor ?? cs.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
