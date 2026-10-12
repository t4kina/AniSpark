import 'package:flutter/material.dart';

/// The app's light or dark theme, coloured with the user's [accent].
///
/// Both share the same structure; only the palette differs. Ink ripples
/// stay transparent: tappable cards give feedback by shrinking instead
/// (see `Pressable`).
ThemeData buildAppTheme(Brightness brightness, Color accent) {
  final isLight = brightness == Brightness.light;
  final background = isLight ? const Color(0xFFD8D8DC) : const Color(0xFF111113);
  final surface = isLight ? const Color(0xFFE2E2E6) : const Color(0xFF1C1C1E);

  OutlineInputBorder inputBorder([BorderSide side = BorderSide.none]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: side);

  return ThemeData(
    brightness: brightness,
    visualDensity: VisualDensity.compact,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    scaffoldBackgroundColor: background,
    colorScheme: isLight
        ? ColorScheme.light(
            primary: accent,
            surface: surface,
            surfaceContainerHighest: const Color(0xFFD0D0D4),
            outline: const Color(0xFFB8B8BC),
            onSurface: const Color(0xFF1A1A2E),
            onSurfaceVariant: Colors.black54,
          )
        : ColorScheme.dark(
            primary: accent,
            surface: surface,
            surfaceContainerLow: surface,
            surfaceContainerHighest: const Color(0xFF2C2C2E),
            outlineVariant: const Color(0xFF38383A),
            outline: const Color(0xFF48484A),
            onSurface: const Color(0xFFEAEAEA),
            onSurfaceVariant: const Color(0xFFAAAAAA),
          ),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: isLight ? const Color(0xFF1A1A2E) : null,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isLight ? const Color(0xFFEFEFF1) : surface,
      height: 64,
      indicatorColor: Colors.transparent,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? accent : Colors.grey,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected)
          ? TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600)
          : const TextStyle(color: Colors.grey, fontSize: 11)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: Colors.grey,
      indicatorColor: accent,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: isLight ? const Color(0xFFE5E7F2) : const Color(0xFF2C2C2E),
      labelStyle: TextStyle(fontSize: 11, color: isLight ? const Color(0xFF1A1A2E) : null),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: isLight ? const BorderSide(color: Color(0xFFD0D2E4)) : null,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isLight ? const Color(0xFFE8EAF4) : const Color(0xFF2C2C2E),
      border: inputBorder(),
      enabledBorder: inputBorder(),
      focusedBorder: inputBorder(BorderSide(color: accent, width: 1)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: const TextStyle(color: Colors.grey),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
    ),
    dividerTheme: DividerThemeData(
      color: isLight ? const Color(0xFFD0D2E4) : const Color(0xFF2C2C2E),
      thickness: 1,
      space: 0,
    ),
    dialogTheme: isLight
        ? const DialogThemeData(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          )
        : null,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // One transition everywhere: Android follows the predictive back
    // gesture, iOS keeps its native swipe-back slide.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    }),
    fontFamily: 'Roboto',
  );
}
