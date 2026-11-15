import 'package:flutter/material.dart';

import 'motion/rounded_hero.dart';

/// The app's logo, [size] wide, with rounded corners.
///
/// Every copy shares one hero tag, so between two pages that both show it
/// (the splash and the login screen) it is one logo that travels and
/// resizes instead of one fading out while another fades in.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.size});

  final double size;

  static const heroTag = 'app-logo';
  static const _asset = 'assets/logo.jpg';
  static const _corners = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: RoundedHero(
        tag: heroTag,
        borderRadius: _corners,
        child: Image.asset(_asset, fit: BoxFit.cover, excludeFromSemantics: true),
      ),
    );
  }
}
