import 'package:flutter/material.dart';

/// Motion tokens shared by every animation, so the whole app moves with one
/// rhythm: [short] for small feedback, [medium] for content changes, [long]
/// for big moves. Durations collapse to zero when the system asks to remove
/// animations (accessibility), see [of].
abstract final class AppMotion {
  /// Press feedback, icon pops and other small state changes.
  static const short = Duration(milliseconds: 150);

  /// Content swaps (skeleton → content), tab changes and list entrances.
  static const medium = Duration(milliseconds: 250);

  /// Large movements, such as a cover flying to the detail page.
  static const long = Duration(milliseconds: 400);

  /// Elements arriving: quick start, gentle stop.
  static const enter = Easing.emphasizedDecelerate;

  /// Elements leaving: gentle start, quick finish.
  static const exit = Easing.emphasizedAccelerate;

  /// Elements that move and stay on screen.
  static const standard = Easing.standard;

  /// Whether the user asked the system to remove animations.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or zero when animations are reduced.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}
