import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_motion.dart';
import '../theme/app_text.dart';
import 'app_button.dart';

/// Opens [builder] (an [AppDialog]) over a dimmed screen. It grows in from
/// slightly smaller, and a tap outside it closes it.
Future<T?> showAppDialog<T>({required BuildContext context, required WidgetBuilder builder}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: AppMotion.of(context, AppMotion.medium),
    pageBuilder: (dialogContext, _, _) => builder(dialogContext),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.exit);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: _startScale, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

const _startScale = 0.94;

/// Asks a yes-or-no question and resolves to whether it was confirmed;
/// closing it any other way is a no.
///
/// [destructive] draws the confirming button in the danger colour, for
/// things that can't be undone.
Future<bool> showAppConfirm({
  required BuildContext context,
  required String title,
  String? message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: title,
      content: message == null ? null : Text(message),
      actions: [
        AppButton(
          label: cancelLabel,
          kind: AppButtonKind.tonal,
          expand: true,
          onPressed: () => Navigator.pop(dialogContext, false),
        ),
        AppButton(
          label: confirmLabel,
          kind: destructive ? AppButtonKind.danger : AppButtonKind.primary,
          expand: true,
          onPressed: () => Navigator.pop(dialogContext, true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The app's dialog: a card with a title, what it has to say and, under
/// it, its buttons side by side.
///
/// [content] scrolls when the screen is too short for it, so the buttons
/// stay in view. [actions] share the width; give them `expand: true`.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.leading,
    this.content,
    this.actions = const [],
  });

  final String title;

  /// Shown before the title, e.g. a logo.
  final Widget? leading;
  final Widget? content;
  final List<Widget> actions;

  static const _maxWidth = 340.0;
  static const _padding = 20.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final leading = this.leading;
    final content = this.content;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              label: title,
              explicitChildNodes: true,
              child: Material(
                color: cs.surface,
                borderRadius: AppRadius.lgAll,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(_padding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (leading != null) ...[leading, const SizedBox(width: AppSpace.md)],
                          Expanded(child: Text(title, style: AppText.headline)),
                        ],
                      ),
                      if (content != null) ...[
                        const SizedBox(height: AppSpace.sm),
                        Flexible(
                          child: SingleChildScrollView(
                            child: DefaultTextStyle.merge(
                              style: AppText.body.copyWith(color: context.colors.textSecondary, height: 1.45),
                              child: content,
                            ),
                          ),
                        ),
                      ],
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: _padding),
                        Row(
                          children: [
                            for (final (i, action) in actions.indexed) ...[
                              if (i > 0) const SizedBox(width: AppSpace.md),
                              Expanded(child: action),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
