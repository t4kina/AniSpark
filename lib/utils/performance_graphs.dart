import 'package:flutter/foundation.dart';

/// Whether the app draws Flutter's frame timing graphs over every screen,
/// to find what stutters on a real phone. Switched on and off from Settings
/// (tapping the version a few times); not kept between launches.
final performanceGraphsNotifier = ValueNotifier<bool>(false);
