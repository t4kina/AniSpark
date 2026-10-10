import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../screens/detail_screen.dart';
import '../../screens/user_profile_screen.dart';
import '../../services/social_api.dart' show asJsonMap;
import '../../utils/activity_text.dart';
import '../../utils/translations.dart' show tr;
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

/// Heart toggle with the like count, for activities and replies.
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

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Tooltip(
      message: tr(isLiked ? 'social_unlike' : 'social_like', lang),
      child: TextButton.icon(
        onPressed: onPressed,
        style: _countButtonStyle(isLiked ? Colors.redAccent : Colors.grey),
        icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, size: 16),
        label: Text('$count'),
      ),
    );
  }
}

/// Reply count that opens the thread.
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
        label: Text('$count'),
      ),
    );
  }
}

/// A user's round avatar that opens their profile.
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
        onTap: () => openUserProfile(context, user),
        child: UserAvatar(
          url: asJsonMap(user?['avatar'])?['large'] as String?,
          size: radius * 2,
        ),
      ),
    );
  }
}
