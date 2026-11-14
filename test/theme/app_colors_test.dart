import 'package:anispark/theme/app_colors.dart';
import 'package:anispark/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const accent = Color(0xFF3DB4F2);

  Future<AppColors> colorsUnder(WidgetTester tester, ThemeData theme) async {
    late AppColors colors;
    // A new key each time: a MaterialApp that only changes theme animates
    // from the old one.
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      theme: theme,
      home: Builder(builder: (context) {
        colors = context.colors;
        return const SizedBox();
      }),
    ));
    return colors;
  }

  testWidgets('the app theme carries the semantic colours of its brightness', (tester) async {
    final light = await colorsUnder(tester, buildAppTheme(Brightness.light, accent));
    final dark = await colorsUnder(tester, buildAppTheme(Brightness.dark, accent));

    expect(light.textSecondary, const AppColors.light().textSecondary);
    expect(dark.textSecondary, const AppColors.dark().textSecondary);
    expect(light.textSecondary, isNot(dark.textSecondary));
  });

  testWidgets('secondary text is legible on both backgrounds', (tester) async {
    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(brightness, accent);
      final colors = await colorsUnder(tester, theme);
      final background = theme.scaffoldBackgroundColor;
      final shown = Color.alphaBlend(colors.textSecondary, background);

      final lighter = [shown.computeLuminance(), background.computeLuminance()].reduce((a, b) => a > b ? a : b);
      final darker = [shown.computeLuminance(), background.computeLuminance()].reduce((a, b) => a < b ? a : b);
      expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(4.5), reason: '$brightness: WCAG AA for text');
    }
  });

  testWidgets('a theme without the extension falls back to the set for its brightness', (tester) async {
    final colors = await colorsUnder(tester, ThemeData(brightness: Brightness.light));

    expect(colors.danger, const AppColors.light().danger);
  });

  test('lerps every colour halfway between two sets', () {
    const from = AppColors.light();
    const to = AppColors.dark();

    final half = from.lerp(to, 0.5);

    expect(half.star, Color.lerp(from.star, to.star, 0.5));
    expect(half.textTertiary, Color.lerp(from.textTertiary, to.textTertiary, 0.5));
    expect(from.lerp(null, 0.5), same(from));
  });

  test('copyWith replaces only what it is given', () {
    const base = AppColors.dark();

    final changed = base.copyWith(danger: const Color(0xFF000000));

    expect(changed.danger, const Color(0xFF000000));
    expect(changed.success, base.success);
  });
}
