import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/people_api.dart';
import '../motion/pressable.dart';
import '../motion/rounded_hero.dart';
import 'people_labels.dart';
import '../app_image.dart';

/// Grid layout of [VoicedCharacterTile]s: two per row on phones.
const voicedCharacterGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 220,
  mainAxisExtent: 196,
  crossAxisSpacing: 10,
  mainAxisSpacing: 10,
);

/// A character a voice actor played (left) next to the media it's from
/// (right); each half opens its own page.
class VoicedCharacterTile extends StatelessWidget {
  const VoicedCharacterTile({
    super.key,
    required this.item,
    this.onCharacterTap,
    this.onMediaTap,
    this.mediaHeroTag,
    this.characterHeroTag,
  });

  final VoicedCharacter item;
  final VoidCallback? onCharacterTap;
  final VoidCallback? onMediaTap;

  /// Tag of the media cover's hero (see `coverHeroTag`), when
  /// [onMediaTap] opens its detail page with it.
  final String? mediaHeroTag;

  /// Tag of the character photo's hero (see `personHeroTag`), when
  /// [onCharacterTap] opens the character with it.
  final String? characterHeroTag;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Half(
                imageUrl: item.character.imageUrl,
                title: item.character.name,
                subtitle: characterRoleLabel(item.role, lang),
                onTap: onCharacterTap,
                heroTag: characterHeroTag,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _Half(
                imageUrl: item.media.coverUrl,
                title: settings.resolveTitle(item.media.title),
                subtitle: mediaFormatAndYear(item.media, lang),
                onTap: onMediaTap,
                heroTag: mediaHeroTag,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Half extends StatelessWidget {
  const _Half({required this.imageUrl, required this.title, this.subtitle, this.onTap, this.heroTag});

  final String? imageUrl;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final imageUrl = this.imageUrl;
    final subtitle = this.subtitle;
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: Pressable(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox.expand(
                  child: RoundedHero(
                    tag: heroTag,
                    child: AppImage(url: imageUrl, cacheWidth: 240, alignment: Alignment.topCenter),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.25),
              ),
              Text(
                subtitle ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: Colors.grey, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
