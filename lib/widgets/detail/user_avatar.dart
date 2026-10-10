import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
    final placeholder = Container(
      width: size,
      height: size,
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.person, size: size * 0.55, color: cs.onSurfaceVariant),
    );
    final url = this.url;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius ?? size / 2),
        child: url == null || url.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}
