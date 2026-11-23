import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_image.dart';

/// A heavily blurred, slightly darkened [url] filling its box: a header
/// background when there's no banner (built from the cover or avatar
/// instead of a flat colour).
class BlurredBackdrop extends StatelessWidget {
  const BlurredBackdrop({super.key, required this.url, this.decodeWidth = defaultDecodeWidth});

  /// The blur hides detail, so a small decode is enough (and cheap).
  static const defaultDecodeWidth = 120;

  final String url;

  /// The width [url] is decoded at. Matching the size a list already
  /// decoded it at reuses that image from memory, so it shows at once.
  final int decodeWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AppImage(url: url, cacheWidth: decodeWidth),
        ),
        const ColoredBox(color: Color(0x33000000)),
      ],
    );
  }
}
