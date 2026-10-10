import 'package:flutter/material.dart';

/// Scaffold backgrounds of the dark and light themes (see main.dart).
const darkBackground = Color(0xFF111113);
const lightBackground = Color(0xFFD8D8DC);

// Luminance window that keeps a 3:1 contrast both with white text on the
// accent and with the accent on the theme background.
const _maxLuminance = 0.30; // white text on the accent
const _darkThemeMinLuminance = 0.12; // accent on the dark background
const _lightThemeMaxLuminance = 0.19; // accent on the light background

/// Turns AniList's `coverImage.color` (e.g. `#f16b50`) into an accent that
/// keeps the cover's hue but stays readable on the current theme. Returns
/// null when there is no usable colour.
Color? mediaAccentColor(String? hex, Brightness brightness) {
  final value = hex?.replaceFirst('#', '');
  if (value == null || value.length != 6) return null;
  final rgb = int.tryParse(value, radix: 16);
  if (rgb == null) return null;

  var hsl = HSLColor.fromColor(Color(0xFF000000 | rgb));
  // Greys stay grey; vivid or washed-out colours are tamed a little.
  if (hsl.saturation >= 0.1) {
    hsl = hsl.withSaturation(hsl.saturation.clamp(0.35, 0.85));
  }

  final (minLuminance, maxLuminance) = brightness == Brightness.dark
      ? (_darkThemeMinLuminance, _maxLuminance)
      : (0.0, _lightThemeMaxLuminance);
  var lightness = hsl.lightness;
  for (var i = 0; i < 100; i++) {
    final luminance = hsl.withLightness(lightness).toColor().computeLuminance();
    if (luminance > maxLuminance && lightness > 0) {
      lightness = (lightness - 0.01).clamp(0.0, 1.0);
    } else if (luminance < minLuminance && lightness < 1) {
      lightness = (lightness + 0.01).clamp(0.0, 1.0);
    } else {
      break;
    }
  }
  return hsl.withLightness(lightness).toColor();
}
