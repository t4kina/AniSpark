import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_text.dart';

/// What a screen shows when it has no content to show: nothing here yet,
/// nothing found, signed out, or a failed load (see `LoadErrorView`). An
/// icon, an optional [title], a [message] and an optional [action], centred.
class StateMessage extends StatelessWidget {
  const StateMessage({super.key, required this.icon, required this.message, this.title, this.action});

  final IconData icon;
  final String? title;
  final String message;

  /// Usually an `AppButton`: the way out of this state.
  final Widget? action;

  static const _badgeSize = 72.0;
  static const _maxTextWidth = 320.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final secondary = context.colors.textSecondary;
    final title = this.title;
    final action = this.action;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxTextWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: _badgeSize,
                height: _badgeSize,
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle),
                child: Icon(icon, size: 32, color: secondary),
              ),
              const SizedBox(height: AppSpace.lg),
              if (title != null) ...[
                Text(title, textAlign: TextAlign.center, style: AppText.headline.copyWith(color: cs.onSurface)),
                const SizedBox(height: AppSpace.xs),
              ],
              Text(message, textAlign: TextAlign.center, style: AppText.body.copyWith(color: secondary, height: 1.4)),
              if (action != null) ...[
                const SizedBox(height: AppSpace.xl),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
