import 'package:flutter/services.dart';

/// Mirrors SettingsProvider.hapticsEnabled so every tap feedback call site
/// can check it without needing a BuildContext or a Provider lookup. Kept
/// in sync by SettingsProvider.load() and setHapticsEnabled().
bool hapticsEnabled = true;

// The app's haptic vocabulary. Each kind of moment has one feel, so the
// phone tells them apart without looking:
//
//  * selection: a value changed under the finger (picker, toggle, tab,
//    crossing a swipe's trigger point).
//  * light: a tap that takes you somewhere or switches something on.
//  * medium: a deliberate gesture was recognised (long press, drag pick-up).
//  * success: something was saved or finished.
//  * error: something the user asked for failed.

void selectionHaptic() {
  if (hapticsEnabled) HapticFeedback.selectionClick();
}

void lightHaptic() {
  if (hapticsEnabled) HapticFeedback.lightImpact();
}

void mediumHaptic() {
  if (hapticsEnabled) HapticFeedback.mediumImpact();
}

void successHaptic() {
  if (hapticsEnabled) HapticFeedback.successNotification();
}

void errorHaptic() {
  if (hapticsEnabled) HapticFeedback.errorNotification();
}
