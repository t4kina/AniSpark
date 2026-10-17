import 'package:anispark/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const accent = Color(0xFF3DB4F2);

  group('buildAppTheme', () {
    test('keeps the light palette', () {
      final theme = buildAppTheme(Brightness.light, accent);

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFD8D8DC));
      expect(theme.colorScheme.primary, accent);
      expect(theme.colorScheme.surface, const Color(0xFFE2E2E6));
      expect(theme.colorScheme.onSurface, const Color(0xFF1A1A2E));
      expect(theme.appBarTheme.foregroundColor, const Color(0xFF1A1A2E));
      expect(theme.navigationBarTheme.backgroundColor, const Color(0xFFEFEFF1));
      expect(theme.chipTheme.side, const BorderSide(color: Color(0xFFD0D2E4)));
      expect(theme.inputDecorationTheme.fillColor, const Color(0xFFE8EAF4));
      expect(theme.dialogTheme.backgroundColor, Colors.white);
      expect(theme.splashColor, Colors.transparent);
    });

    test('keeps the dark palette', () {
      final theme = buildAppTheme(Brightness.dark, accent);

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF111113));
      expect(theme.colorScheme.primary, accent);
      expect(theme.colorScheme.surface, const Color(0xFF1C1C1E));
      expect(theme.colorScheme.surfaceContainerHighest, const Color(0xFF2C2C2E));
      expect(theme.colorScheme.outlineVariant, const Color(0xFF38383A));
      expect(theme.appBarTheme.foregroundColor, isNull);
      expect(theme.navigationBarTheme.backgroundColor, const Color(0xFF1C1C1E));
      expect(theme.chipTheme.side, isNull);
      expect(theme.inputDecorationTheme.fillColor, const Color(0xFF2C2C2E));
      expect(theme.dialogTheme.backgroundColor, isNull);
    });

    test('colours the selected navigation item with the accent', () {
      final theme = buildAppTheme(Brightness.dark, accent);

      final selected = theme.navigationBarTheme.iconTheme!.resolve({WidgetState.selected});
      final idle = theme.navigationBarTheme.iconTheme!.resolve({});

      expect(selected?.color, accent);
      expect(idle?.color, Colors.grey);
    });

    test('uses one page transition per platform, with predictive back on Android', () {
      for (final brightness in Brightness.values) {
        final builders = buildAppTheme(brightness, accent).pageTransitionsTheme.builders;

        expect(builders[TargetPlatform.android], isA<PredictiveBackPageTransitionsBuilder>());
        expect(builders[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
      }
    });

    test('shows snack bars floating with rounded corners', () {
      final snackBars = buildAppTheme(Brightness.light, accent).snackBarTheme;

      expect(snackBars.behavior, SnackBarBehavior.floating);
      expect(snackBars.shape, isA<RoundedRectangleBorder>());
    });
  });
}
