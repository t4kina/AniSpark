import 'package:anispark/utils/media_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const samples = ['#ffe4a1', '#f16b50', '#1a1a1a', '#0a0a2a', '#43a5f0', '#e4f1a1', '#f0f0ff', '#5de43e'];

  group('mediaAccentColor', () {
    test('parses an AniList hex colour', () {
      expect(mediaAccentColor('#f16b50', Brightness.dark), isNotNull);
      expect(mediaAccentColor('f16b50', Brightness.light), isNotNull);
    });

    test('returns null for missing or malformed colours', () {
      expect(mediaAccentColor(null, Brightness.dark), isNull);
      expect(mediaAccentColor('', Brightness.dark), isNull);
      expect(mediaAccentColor('#zzzzzz', Brightness.dark), isNull);
      expect(mediaAccentColor('#fff', Brightness.dark), isNull);
    });

    test('stays readable against the theme background and under white text', () {
      for (final hex in samples) {
        for (final brightness in Brightness.values) {
          final accent = mediaAccentColor(hex, brightness)!;
          final background = brightness == Brightness.dark ? darkBackground : lightBackground;

          expect(_contrast(accent, background), greaterThanOrEqualTo(3), reason: '$hex vs $brightness background');
          expect(_contrast(accent, Colors.white), greaterThanOrEqualTo(3), reason: 'white text on $hex ($brightness)');
        }
      }
    });

    test('keeps the hue of the cover', () {
      final accent = mediaAccentColor('#f16b50', Brightness.dark)!;

      expect(HSLColor.fromColor(accent).hue, closeTo(HSLColor.fromColor(const Color(0xFFF16B50)).hue, 1));
    });

    test('does not invent a hue for grey covers', () {
      final accent = mediaAccentColor('#808080', Brightness.dark)!;

      expect(HSLColor.fromColor(accent).saturation, lessThan(0.05));
    });
  });
}
