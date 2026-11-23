import 'package:flutter/material.dart';

/// Colours with a meaning, beyond the theme's colour scheme. They follow
/// the light or dark theme, unlike a fixed `Colors.grey`, which is too faint
/// on the light background. Read them with `context.colors`.
///
/// The accent is not here: it is `colorScheme.primary`, the colour the user
/// picked in Settings.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.textSecondary,
    required this.textTertiary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.star,
  });

  const AppColors.light()
      : textSecondary = const Color(0x99000000),
        textTertiary = const Color(0x61000000),
        success = const Color(0xFF2E7D32),
        warning = const Color(0xFFBF4A00),
        danger = const Color(0xFFC62828),
        star = const Color(0xFFF5A524);

  const AppColors.dark()
      : textSecondary = const Color(0xFFAAAAAA),
        textTertiary = const Color(0xFF77777C),
        success = const Color(0xFF4CAF50),
        warning = const Color(0xFFFFA726),
        danger = const Color(0xFFEF5350),
        star = const Color(0xFFFFC107);

  /// Supporting text: subtitles, metadata, empty-state messages.
  final Color textSecondary;

  /// Text that should recede: placeholders, disabled labels, hints.
  final Color textTertiary;

  /// Something went well or is positive: completed, added, high affinity.
  final Color success;

  /// Something needs care: spoilers, paused.
  final Color warning;

  /// Destructive actions and failures.
  final Color danger;

  /// Score stars.
  final Color star;

  @override
  AppColors copyWith({
    Color? textSecondary,
    Color? textTertiary,
    Color? success,
    Color? warning,
    Color? danger,
    Color? star,
  }) =>
      AppColors(
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        star: star ?? this.star,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return AppColors(
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      star: mix(star, other.star),
    );
  }
}

extension AppColorsContext on BuildContext {
  /// The semantic colours of the current theme. A theme built without them
  /// (a bare `MaterialApp` in a test) gets the set matching its brightness.
  AppColors get colors {
    final theme = Theme.of(this);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.light ? const AppColors.light() : const AppColors.dark());
  }
}
