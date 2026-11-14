import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// The app's network image. Its box is the surface colour until the image
/// arrives, which then fades in over it; an image already in memory shows
/// at once. No [url], or one that fails, leaves the surface colour (and the
/// [placeholder], or the [error] given for a failure) in place.
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.url,
    required this.cacheWidth,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fadeIn = AppMotion.short,
    this.fill = true,
    this.placeholder,
    this.error,
    this.color,
    this.colorBlendMode,
  });

  final String? url;

  /// The width the image is decoded at, in physical pixels: about what it
  /// is shown at. Two places that show the same image at the same
  /// [cacheWidth] share it in memory.
  final int cacheWidth;

  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  /// How long the image takes to appear once loaded; zero when animations
  /// are reduced.
  final Duration fadeIn;

  /// Whether the surface colour is painted behind the image. Off for an
  /// image layered over something else, which must stay visible until this
  /// one has arrived.
  final bool fill;

  /// Shown while there is no image, over the surface colour.
  final Widget? placeholder;

  /// Shown in place of an image that failed to load; the [placeholder]
  /// unless given.
  final Widget? error;
  final Color? color;
  final BlendMode? colorBlendMode;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final idle = placeholder ?? const SizedBox.shrink();
    Widget image = url == null || url.isEmpty
        ? idle
        : CachedNetworkImage(
            imageUrl: url,
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
            memCacheWidth: cacheWidth,
            color: color,
            colorBlendMode: colorBlendMode,
            fadeInDuration: AppMotion.of(context, fadeIn),
            // The placeholder leaves at once: the image fades in over
            // whatever is behind it.
            fadeOutDuration: Duration.zero,
            placeholder: (_, _) => idle,
            errorWidget: (_, _, _) => error ?? idle,
          );
    if (fill) {
      image = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: image);
    }
    if (width == null && height == null) return image;
    return SizedBox(width: width, height: height, child: image);
  }
}
