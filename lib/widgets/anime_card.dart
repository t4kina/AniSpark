import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../screens/detail_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_motion.dart';
import '../utils/haptics.dart';
import '../utils/translations.dart' show tr;
import 'entry_editor/entry_editor_sheet.dart';
import 'motion/cover_hero.dart';
import 'motion/pressable.dart';
import 'motion/rounded_hero.dart';

class AnimeCard extends StatelessWidget {
  final dynamic animeData; // from API
  final bool showScore;

  /// The list this card is in (see `coverHeroTag`), so its cover flies into
  /// the detail page; unique on the screen. No flight without one.
  final String? heroScope;

  const AnimeCard({
    super.key,
    required this.animeData,
    this.showScore = true,
    this.heroScope,
  });

  static const _coverRadius = BorderRadius.all(Radius.circular(8));
  static const _titleSize = 12.0;
  static const _scoreSize = 11.0;
  static const _lineHeight = 1.3;

  /// Long-press quick add: opens the entry editor, which looks the media up
  /// in the user's list (a new entry starts as Planning). Does nothing when
  /// logged out.
  void _quickAdd(BuildContext context) {
    final data = animeData;
    if (data is! Map<String, dynamic> || !context.read<AuthService>().isLoggedIn) return;
    final media = EditorMedia.fromMedia(data);
    if (media == null) return;
    mediumHaptic();
    showEntryEditor(context, media: media, entryKnown: false);
  }

  @override
  Widget build(BuildContext context) {
    final id = animeData['id'] as int?;
    final title = context.select<SettingsProvider, String>(
      (s) => s.resolveTitle(animeData['title'] as Map<String, dynamic>?),
    );
    final image = animeData['coverImage']?['large'] as String?;
    final score = animeData['averageScore'];
    final lang = context.select<SettingsProvider, String>((s) => s.language);
    final loggedIn = context.select<AuthService, bool>((a) => a.isLoggedIn);
    final canQuickAdd = id != null && loggedIn;
    final scope = heroScope;
    final heroTag = id != null && scope != null ? coverHeroTag(scope, id) : null;
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    final textScaler = MediaQuery.textScalerOf(context);

    final card = Pressable(
      onTap: id == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetailScreen(animeId: id, heroTag: heroTag, initialCoverUrl: image),
                ),
              ),
      onLongPress: id == null ? null : () => _quickAdd(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: RoundedHero(
                tag: heroTag,
                borderRadius: _coverRadius,
                child: image != null
                    ? CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        memCacheWidth: 240,
                        fadeInDuration: AppMotion.of(context, AppMotion.short),
                        fadeOutDuration: Duration.zero,
                        placeholder: (_, _) => placeholder,
                        errorWidget: (_, _, _) => placeholder,
                      )
                    : placeholder,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Always two title lines (and a score line) tall, so covers in a
          // row or grid line up whatever the title's length or a missing score.
          SizedBox(
            height: textScaler.scale(_titleSize) * _lineHeight * 2,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              strutStyle: const StrutStyle(fontSize: _titleSize, height: _lineHeight, forceStrutHeight: true),
              style: const TextStyle(fontSize: _titleSize, height: _lineHeight, fontWeight: FontWeight.w600),
            ),
          ),
          if (showScore)
            SizedBox(
              height: textScaler.scale(_scoreSize) * _lineHeight,
              child: score == null
                  ? null
                  : Row(
                      children: [
                        const Icon(Icons.star, size: 12, color: Color(0xFFFFC107)),
                        const SizedBox(width: 2),
                        Text(
                          '${(score / 10).toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: _scoreSize, color: Colors.grey),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
    // Screen readers can't discover a long press, so quick add is also
    // offered as a named action.
    final quickAdd = tr('quick_add_action', lang);
    return Semantics(
      onLongPressHint: canQuickAdd ? quickAdd : null,
      customSemanticsActions:
          canQuickAdd ? {CustomSemanticsAction(label: quickAdd): () => _quickAdd(context)} : null,
      child: card,
    );
  }
}
