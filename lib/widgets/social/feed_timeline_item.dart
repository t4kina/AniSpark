import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/social_api.dart' show asJsonMap;
import '../../theme/app_colors.dart';
import '../../theme/app_layout.dart';
import '../../theme/app_text.dart';
import '../../utils/activity_status.dart';
import '../../utils/activity_text.dart';
import '../../utils/translations.dart' show tr;
import '../app_image.dart';
import '../dev_badge.dart';
import '../media_preview.dart';
import '../motion/pressable.dart';
import 'social_widgets.dart';

/// One activity of the feed, as an entry of a timeline: the author's avatar
/// on a line that runs down the page, who did what, the title or the text,
/// and the cover at the right. No card around it.
///
/// [dayLabel] is the heading ("Today", "Yesterday", a date) shown above the
/// first entry of each day; null for the rest.
class FeedTimelineItem extends StatelessWidget {
  const FeedTimelineItem({
    super.key,
    required this.activity,
    required this.lang,
    required this.onToggleLike,
    required this.onOpenThread,
    this.dayLabel,
  });

  final Map<String, dynamic> activity;
  final String lang;
  final VoidCallback onToggleLike;
  final VoidCallback onOpenThread;
  final String? dayLabel;

  // Long posts are cut in the feed; the thread shows them in full.
  static const _maxTextLines = 10;

  static const coverSize = Size(40, 58);
  static const _avatarRadius = 14.0;

  /// The avatar's tap area is this wide whatever its drawn size (see
  /// `ProfileAvatar`), so its centre, and the line through it, is half in.
  static const _avatarBox = 44.0;
  static const _edge = AppSpace.sm;
  static const _lineWidth = 2.0;

  /// Tells this entry's avatar apart from the author's other entries.
  String get _heroScope => 'feed-${activity['id']}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = dayLabel;
    final user = asJsonMap(activity['user']);
    final entry = Stack(
      children: [
        // The line the day's entries hang from, behind the avatars.
        Positioned(
          left: _edge + _avatarBox / 2 - _lineWidth / 2,
          top: 0,
          bottom: 0,
          width: _lineWidth,
          child: ColoredBox(color: cs.outlineVariant),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(_edge, 6, AppSpace.md, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  // A ring of the page's own colour, so the line stops short
                  // of the avatar instead of running into it.
                  Container(
                    width: _avatarRadius * 2 + 6,
                    height: _avatarRadius * 2 + 6,
                    decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, shape: BoxShape.circle),
                  ),
                  ProfileAvatar(user: user, radius: _avatarRadius, heroScope: _heroScope),
                ],
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: _content(context, user)),
              ..._cover(context),
            ],
          ),
        ),
      ],
    );
    if (label == null) return entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xs),
          child: Text(
            label.toUpperCase(),
            style: AppText.overline.copyWith(color: context.colors.textSecondary),
          ),
        ),
        entry,
      ],
    );
  }

  Widget _content(BuildContext context, Map<String, dynamic>? user) {
    final cs = Theme.of(context).colorScheme;
    final secondary = context.colors.textSecondary;
    final isText = activity['type'] == 'TEXT';
    final username = user?['name'] as String? ?? tr('feed_unknown', lang);
    final action = isText ? null : activityStatusText(activity['status'] as String?, activity['progress'], lang);
    return Padding(
      // Level with the avatar's centre line.
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            child: Pressable.dim(
              onTap: () => openUserProfile(context, user, heroScope: _heroScope),
              child: Text.rich(
                TextSpan(
                  style: AppText.footnote,
                  children: [
                    TextSpan(text: username, style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
                    ?devBadgeSpan(user?['name'] as String?, fontSize: AppText.footnote.fontSize!),
                    if (action != null) TextSpan(text: ' $action', style: TextStyle(color: secondary)),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 2),
          if (isText) _text(context) else _title(context),
          Row(
            children: [
              Expanded(
                child: Text(
                  relativeTime(activity['createdAt'] as int? ?? 0, lang),
                  style: AppText.micro.copyWith(color: secondary),
                ),
              ),
              ReplyCountButton(count: activity['replyCount'] as int? ?? 0, onPressed: onOpenThread),
              LikeButton(
                isLiked: activity['isLiked'] == true,
                count: activity['likeCount'] as int? ?? 0,
                onPressed: onToggleLike,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context) {
    final titleMap = asJsonMap(asJsonMap(activity['media'])?['title']);
    final title =
        titleMap == null ? tr('feed_unknown', lang) : context.read<SettingsProvider>().resolveTitle(titleMap);
    return Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppText.body.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _text(BuildContext context) {
    final text = activityPlainText(activity['text'] as String?, lang);
    final style = AppText.body.copyWith(color: context.colors.textSecondary);
    return Pressable.dim(
      onTap: onOpenThread,
      child: text.isEmpty
          ? Text(tr('social_media_post', lang), style: style.copyWith(fontStyle: FontStyle.italic))
          : Text(text, maxLines: _maxTextLines, overflow: TextOverflow.ellipsis, style: style),
    );
  }

  /// The cover of what the activity is about, when it has one: a tap opens
  /// it, holding it previews it.
  List<Widget> _cover(BuildContext context) {
    final media = asJsonMap(activity['media']);
    final cover = asJsonMap(media?['coverImage'])?['large'] as String?;
    final mediaId = media?['id'] as int?;
    if (media == null || cover == null) return const [];
    return [
      const SizedBox(width: AppSpace.md),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Pressable(
          onTap: mediaId == null ? null : () => openMediaDetail(context, mediaId),
          onLongPress: mediaId == null ? null : () => showMediaPreview(context, media: media),
          child: ClipRRect(
            borderRadius: AppRadius.smAll,
            child: SizedBox.fromSize(size: coverSize, child: AppImage(url: cover, cacheWidth: 120)),
          ),
        ),
      ),
    ];
  }
}
