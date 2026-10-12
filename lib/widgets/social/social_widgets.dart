import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../screens/detail_screen.dart';
import '../../screens/user_profile_screen.dart';
import '../../services/social_api.dart' show asJsonMap;
import '../../utils/activity_text.dart';
import '../../utils/translations.dart' show tr;
import '../motion/animated_count.dart';
import '../motion/pop_on_change.dart';
import '../user_avatar.dart';

/// Opens the profile of an AniList `user` object (`{id, name, avatar}`).
void openUserProfile(BuildContext context, Map<String, dynamic>? user) {
  final id = user?['id'] as int?;
  if (id == null) return;
  final lang = context.read<SettingsProvider>().language;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => UserProfileScreen(
        userId: id,
        name: user?['name'] as String? ?? tr('feed_unknown', lang),
        avatarUrl: asJsonMap(user?['avatar'])?['large'] as String?,
      ),
    ),
  );
}

/// Opens the anime/manga page of [mediaId].
void openMediaDetail(BuildContext context, int mediaId) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailScreen(animeId: mediaId)),
    );

/// Activity or reply text as readable plain text, with spoilers hidden.
String activityPlainText(String? raw, String lang) =>
    cleanActivityText(raw, spoilerLabel: tr('social_spoiler', lang));

ButtonStyle _countButtonStyle(Color color) => TextButton.styleFrom(
      foregroundColor: color,
      minimumSize: const Size(48, 40),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 12),
    );

/// Heart toggle with the like count, for activities and replies. Liking
/// pops the heart with a light haptic tap and the count rolls to its new
/// value; unliking only rolls the count.
class LikeButton extends StatelessWidget {
  const LikeButton({
    super.key,
    required this.isLiked,
    required this.count,
    required this.onPressed,
  });

  final bool isLiked;
  final int count;
  final VoidCallback? onPressed;

  void _press(VoidCallback onPressed) {
    if (!isLiked) HapticFeedback.lightImpact();
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final onPressed = this.onPressed;
    return Tooltip(
      message: tr(isLiked ? 'social_unlike' : 'social_like', lang),
      child: TextButton.icon(
        onPressed: onPressed == null ? null : () => _press(onPressed),
        style: _countButtonStyle(isLiked ? Colors.redAccent : Colors.grey),
        icon: PopOnChange(
          value: isLiked,
          when: (liked) => liked == true,
          child: Icon(isLiked ? Icons.favorite : Icons.favorite_border, size: 16),
        ),
        label: AnimatedCount(value: count),
      ),
    );
  }
}

/// Reply count that opens the thread; the count rolls when it changes.
class ReplyCountButton extends StatelessWidget {
  const ReplyCountButton({super.key, required this.count, required this.onPressed});

  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Tooltip(
      message: tr('social_replies', lang),
      child: TextButton.icon(
        onPressed: onPressed,
        style: _countButtonStyle(Colors.grey),
        icon: const Icon(Icons.chat_bubble_outline, size: 16),
        label: AnimatedCount(value: count),
      ),
    );
  }
}

/// Smallest comfortable touch target.
const _minTapSize = 44.0;

/// A user's round avatar that opens their profile. The hit area is at least
/// 44x44 even when the avatar is drawn smaller.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.user, this.radius = 18});

  final Map<String, dynamic>? user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: user?['name'] as String?,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openUserProfile(context, user),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: _minTapSize, minHeight: _minTapSize),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: UserAvatar(
              url: asJsonMap(user?['avatar'])?['large'] as String?,
              size: radius * 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// A user's name (or any inline label) as a button with a hit area at least
/// 44px high.
class TappableUserName extends StatelessWidget {
  const TappableUserName({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minTapSize),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: child,
          ),
        ),
      ),
    );
  }
}
