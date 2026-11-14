import 'package:flutter/widgets.dart';

/// Corner radii. Four steps and a pill cover every shape in the app; a
/// radius outside this scale is a sign the shape should be one of them.
abstract final class AppRadius {
  /// Tags, progress bars and other slivers of colour.
  static const xs = 4.0;

  /// Small covers, list tiles and inputs.
  static const sm = 8.0;

  /// Cards, buttons and posters.
  static const md = 12.0;

  /// Sheets and the big cards that hold other cards.
  static const lg = 20.0;

  /// Fully rounded ends, whatever the height.
  static const pill = 999.0;

  static const xsAll = BorderRadius.all(Radius.circular(xs));
  static const smAll = BorderRadius.all(Radius.circular(sm));
  static const mdAll = BorderRadius.all(Radius.circular(md));
  static const lgAll = BorderRadius.all(Radius.circular(lg));
  static const pillAll = BorderRadius.all(Radius.circular(pill));

  /// The top corners of a bottom sheet.
  static const sheet = BorderRadius.vertical(top: Radius.circular(lg));
}

/// Spacing, on a 4-point grid.
abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// The margin between a screen's edge and its content.
  static const page = lg;
}
