import 'package:flutter/material.dart';

/// The colours of one of the app's themes, as the dark theme wears them:
/// the page, the surfaces on it, the lines between things and the text.
/// Only the classic theme also comes in light (see `buildAppTheme`).
@immutable
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.raised,
    required this.line,
    required this.strongLine,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    this.accent,
    this.hasLight = false,
  });

  /// The page behind everything.
  final Color background;

  /// Cards, sheets, grouped rows and the navigation bar.
  final Color surface;

  /// What sits on a surface: chips, fields, dividers between rows.
  final Color raised;

  /// Hairlines.
  final Color line;

  /// Outlines that must show.
  final Color strongLine;

  final Color text;
  final Color textSecondary;
  final Color textTertiary;

  /// The theme's own accent, or null to wear the one picked in Settings.
  final Color? accent;

  /// Whether the theme also comes in light, following Appearance.
  final bool hasLight;
}

/// The theme the app has always had.
const classicTheme = 'Classic';

/// Every theme, in the order Settings shows them. The keys are what is
/// stored; Settings shows them as `theme_<key in lower case>`.
const appThemes = <String, AppPalette>{
  classicTheme: AppPalette(
    background: Color(0xFF111113),
    surface: Color(0xFF1C1C1E),
    raised: Color(0xFF2C2C2E),
    line: Color(0xFF38383A),
    strongLine: Color(0xFF48484A),
    text: Color(0xFFEAEAEA),
    textSecondary: Color(0xFFAAAAAA),
    textTertiary: Color(0xFF77777C),
    hasLight: true,
  ),
  // The lilac of the round 8 mockups.
  'Lilac': AppPalette(
    background: Color(0xFF0F0D15),
    surface: Color(0xFF1B1824),
    raised: Color(0xFF2B2738),
    line: Color(0xFF332E44),
    strongLine: Color(0xFF4A4560),
    text: Color(0xFFF3F1FA),
    textSecondary: Color(0xFFA7A1BA),
    textTertiary: Color(0xFF6F6983),
    accent: Color(0xFF8B7CFF),
  ),
  'Midnight': AppPalette(
    background: Color(0xFF0A0F1C),
    surface: Color(0xFF131B2E),
    raised: Color(0xFF1E2940),
    line: Color(0xFF26324B),
    strongLine: Color(0xFF3A4865),
    text: Color(0xFFEAF0FA),
    textSecondary: Color(0xFF9AA8C0),
    textTertiary: Color(0xFF64728C),
    accent: Color(0xFF4FC3F7),
  ),
  'Sakura': AppPalette(
    background: Color(0xFF140E12),
    surface: Color(0xFF21171D),
    raised: Color(0xFF31222B),
    line: Color(0xFF3A2832),
    strongLine: Color(0xFF563B49),
    text: Color(0xFFFAEFF4),
    textSecondary: Color(0xFFBFA3B0),
    textTertiary: Color(0xFF85697A),
    accent: Color(0xFFFF7EB6),
  ),
  'Forest': AppPalette(
    background: Color(0xFF0C120F),
    surface: Color(0xFF151E19),
    raised: Color(0xFF213028),
    line: Color(0xFF283A30),
    strongLine: Color(0xFF3B5446),
    text: Color(0xFFECF5EF),
    textSecondary: Color(0xFF9DB3A6),
    textTertiary: Color(0xFF67806F),
    accent: Color(0xFF4ADE80),
  ),
  // Pure black for OLED screens, in the accent picked in Settings.
  'Black': AppPalette(
    background: Color(0xFF000000),
    surface: Color(0xFF111112),
    raised: Color(0xFF1E1E20),
    line: Color(0xFF29292B),
    strongLine: Color(0xFF3A3A3C),
    text: Color(0xFFF2F2F2),
    textSecondary: Color(0xFFA0A0A0),
    textTertiary: Color(0xFF6C6C70),
  ),
};
