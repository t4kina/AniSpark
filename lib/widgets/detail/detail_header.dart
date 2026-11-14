import 'package:flutter/material.dart';

import '../app_image.dart';

/// The top card of the media detail page: [banner], the [cover] straddling
/// its bottom edge and [info] (title, studios, stats) under it. The page
/// lays it out the same while loading, so a cover flying in from a list
/// lands where it stays.
class DetailHeader extends StatelessWidget {
  const DetailHeader({super.key, required this.banner, required this.cover, required this.info});

  static const bannerHeight = 200.0;
  static const coverTop = 80.0;
  static const coverSize = Size(130, 190);
  static const coverRadius = BorderRadius.all(Radius.circular(10));

  final Widget banner;
  final Widget cover;
  final Widget info;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: bannerHeight, child: banner),
              // Room for the part of the cover below the banner.
              const SizedBox(height: coverTop),
              info,
            ],
          ),
          // The banner fades into the card.
          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: Container(
              height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [surface.withValues(alpha: 0), surface],
                  stops: const [0.3, 1.0],
                ),
              ),
            ),
          ),
          Positioned(top: coverTop, child: SizedBox.fromSize(size: coverSize, child: cover)),
        ],
      ),
    );
  }
}

/// The detail page's cover: [previewUrl], the cover the opening list showed
/// (already cached, so it's there at once), with the full-size [url] fading
/// in over it once it has loaded.
class DetailCoverImage extends StatelessWidget {
  const DetailCoverImage({super.key, this.previewUrl, this.url});

  /// Matches the lists' covers, so the preview is usually decoded already.
  static const previewCacheWidth = 240;
  static const cacheWidth = 260;

  final String? previewUrl;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final preview = previewUrl;
    final full = url;
    return Stack(
      fit: StackFit.expand,
      children: [
        AppImage(
          url: preview,
          cacheWidth: previewCacheWidth,
          // Lists decode covers at other widths too; when this one isn't
          // cached it appears without a fade, so landing never flickers.
          fadeIn: Duration.zero,
        ),
        // Sharpens over the preview, which stays put underneath.
        if (full != null && full != preview) AppImage(url: full, cacheWidth: cacheWidth, fill: false),
      ],
    );
  }
}
