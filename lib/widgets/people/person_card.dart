import 'package:flutter/material.dart';

import '../motion/pressable.dart';
import '../motion/rounded_hero.dart';
import '../user_avatar.dart';

/// A round photo with a name and a grey line under it (a role, a dub
/// language…), for horizontal rows of people.
class PersonCard extends StatelessWidget {
  const PersonCard({
    super.key,
    required this.name,
    this.imageUrl,
    this.subtitle,
    this.onTap,
    this.avatarSize = defaultAvatarSize,
    this.heroTag,
  });

  static const defaultAvatarSize = 72.0;

  /// Room for the photo, two lines of name and two of subtitle.
  static double rowHeight({double avatarSize = defaultAvatarSize}) => avatarSize + 82;

  final String name;
  final String? imageUrl;
  final String? subtitle;
  final VoidCallback? onTap;
  final double avatarSize;

  /// Tag of the photo's hero (see `personHeroTag`), when [onTap] opens
  /// the person's page with it.
  final String? heroTag;
  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: Pressable(
          onTap: onTap,
          child: SizedBox(
            width: avatarSize + 20,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  RoundedHero(
                    tag: heroTag,
                    borderRadius: BorderRadius.circular(avatarSize / 2),
                    child: UserAvatar(url: imageUrl, size: avatarSize),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.25),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10.5, color: Colors.grey, height: 1.25),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
