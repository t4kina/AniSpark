import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_layout.dart';
import '../../theme/app_text.dart';
import '../../utils/translations.dart';

/// Full-page "couldn't load" message with a retry button.
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final secondary = context.colors.textSecondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: secondary),
            const SizedBox(height: AppSpace.md),
            Text(
              tr('load_error', lang),
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: secondary),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(tr('retry', lang)),
            ),
          ],
        ),
      ),
    );
  }
}
