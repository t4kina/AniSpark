import 'package:flutter/material.dart';

/// The app's type scale: every text is one of these steps, so headings and
/// captions weigh the same on every screen. The styles carry no colour (they
/// take the theme's), so a caller only adds what is particular to it:
/// `AppText.footnote.copyWith(color: context.colors.textSecondary)`.
abstract final class AppText {
  /// The one big title of a screen, such as a profile's name.
  static const largeTitle = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4);

  /// A page or dialog title.
  static const title = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2);

  /// A section or sheet heading.
  static const headline = TextStyle(fontSize: 17, fontWeight: FontWeight.w700);

  /// The main line of a row or a card, and button labels.
  static const subhead = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

  /// Running text.
  static const body = TextStyle(fontSize: 14, fontWeight: FontWeight.w400);

  /// Secondary lines under a title.
  static const footnote = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);

  /// Metadata: dates, counts, formats.
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);

  /// The smallest readable text: badges and chart labels.
  static const micro = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);

  /// Small spaced-out caps above a group of content.
  static const overline = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6);
}
