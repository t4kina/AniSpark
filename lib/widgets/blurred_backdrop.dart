import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A heavily blurred, slightly darkened [url] filling its box: a header
/// background when there's no banner (built from the cover or avatar
/// instead of a flat colour).
class BlurredBackdrop extends StatelessWidget {
  const BlurredBackdrop({super.key, required this.url});

  /// The blur hides detail, so a small decode is enough (and cheap).
  static const decodeWidth = 120;

  final String url;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: decodeWidth,
            fadeOutDuration: Duration.zero,
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          ),
        ),
        const ColoredBox(color: Color(0x33000000)),
      ],
    );
  }
}
