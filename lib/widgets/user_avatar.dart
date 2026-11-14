import 'package:flutter/material.dart';

import 'app_image.dart';

/// A user's avatar, clipped to [radius] (a circle by default), with a
/// person icon while it loads or when there is none. Decorative: the user's
/// name is read out by the surrounding row instead.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.url, this.size = 44, this.radius});

  final String? url;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius ?? size / 2),
        child: AppImage(
          url: url,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          width: size,
          height: size,
          placeholder: Icon(Icons.person, size: size * 0.55, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
