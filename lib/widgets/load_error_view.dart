import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../utils/translations.dart';
import 'app_button.dart';
import 'state_message.dart';

/// The app's "couldn't load" state: the message and a retry button. Every
/// screen and sheet whose first load can fail shows this one.
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;

  /// Replaces the general "couldn't load the content".
  final String? message;

  @override
  Widget build(BuildContext context) {
    final lang = context.select<SettingsProvider, String>((s) => s.language);
    return StateMessage(
      icon: Icons.wifi_off_rounded,
      message: message ?? tr('load_error', lang),
      action: AppButton(label: tr('retry', lang), icon: Icons.refresh_rounded, onPressed: onRetry),
    );
  }
}
