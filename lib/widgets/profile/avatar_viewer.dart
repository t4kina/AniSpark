import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_layout.dart';
import '../../theme/app_motion.dart';
import '../motion/rounded_hero.dart';

/// Opens [url], a profile picture, large over a darkened page. Tagged
/// [heroTag], the picture that was tapped grows into it and shrinks back
/// when it closes; a tap anywhere closes it.
Future<void> showAvatarViewer(BuildContext context, {required String url, required Object heroTag}) =>
    Navigator.push(
      context,
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        transitionDuration: AppMotion.of(context, AppMotion.long),
        reverseTransitionDuration: AppMotion.of(context, AppMotion.medium),
        pageBuilder: (_, _, _) => AvatarViewer(url: url, heroTag: heroTag),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );

/// A profile picture as large as the screen allows, rounded, with pinch to
/// zoom. See [showAvatarViewer].
class AvatarViewer extends StatelessWidget {
  const AvatarViewer({super.key, required this.url, required this.heroTag});

  final String url;
  final Object heroTag;

  /// Its corners: the circle it came from opens into a rounded square.
  static const radius = BorderRadius.all(Radius.circular(AppRadius.lg));

  /// Room left around it on a phone.
  static const _margin = AppSpace.xl;

  /// No larger than this on a wide screen.
  static const _maxSide = 480.0;

  @override
  Widget build(BuildContext context) {
    final side = (MediaQuery.sizeOf(context).shortestSide - 2 * _margin).clamp(0.0, _maxSide);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: SizedBox.square(
              dimension: side,
              child: RoundedHero(
                tag: heroTag,
                borderRadius: radius,
                // Decoded at full size: it is shown large and zoomed into.
                child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
