import 'package:flutter/services.dart';

/// Mirrors SettingsProvider.hapticsEnabled so every tap feedback call site
/// can check it without needing a BuildContext or a Provider lookup. Kept
/// in sync by SettingsProvider.load() and setHapticsEnabled().
bool hapticsEnabled = true;

void selectionHaptic() {
  if (hapticsEnabled) HapticFeedback.selectionClick();
}

void lightHaptic() {
  if (hapticsEnabled) HapticFeedback.lightImpact();
}

void mediumHaptic() {
  if (hapticsEnabled) HapticFeedback.mediumImpact();
}
