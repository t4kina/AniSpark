import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../screens/character_screen.dart';
import '../../screens/detail_screen.dart';
import '../motion/cover_hero.dart';
import '../motion/pressable.dart';
import '../motion/rounded_hero.dart';
import '../app_image.dart';

/// A favourite anime or manga in a profile's horizontal row: shrinks while
/// pressed and its cover flies into the detail page. [heroScope] must be
/// unique on the screen (see `coverHeroTag`).
class FavouriteMediaCard extends StatelessWidget {
  const FavouriteMediaCard({super.key, required this.media, required this.heroScope});

  /// An AniList `Media` object (`{id, title, coverImage}`).
  final Map<String, dynamic> media;
  final String heroScope;

  @override
  Widget build(BuildContext context) {
    final id = media['id'] as int?;
    final image = (media['coverImage'] as Map?)?['large'] as String?;
    final title = context.select<SettingsProvider, String>(
        (settings) => settings.resolveTitle(media['title'] as Map<String, dynamic>?));
    final heroTag = id == null ? null : coverHeroTag(heroScope, id);
    final cover = RoundedHero(
      tag: heroTag,
      borderRadius: BorderRadius.circular(8),
      child: AppImage(url: image, cacheWidth: 200, width: 100, height: 140),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Pressable(
        onTap: id == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetailScreen(animeId: id, heroTag: heroTag, initialCoverUrl: image),
                  ),
                ),
        child: SizedBox(
          width: 100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              const SizedBox(height: 4),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A favourite character in a profile's horizontal row; shrinks while
/// pressed and opens the character's page.
class FavouriteCharacterCard extends StatelessWidget {
  const FavouriteCharacterCard({super.key, required this.character});

  /// An AniList `Character` object (`{id, name, image}`).
  final Map<String, dynamic> character;

  @override
  Widget build(BuildContext context) {
    final id = character['id'] as int?;
    final image = (character['image'] as Map?)?['medium'] as String?;
    final name = (character['name'] as Map?)?['full'] as String? ?? '';
    final heroTag = id == null ? null : personHeroTag('favourite-characters', id);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Pressable(
        onTap: id == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CharacterScreen(characterId: id, name: name, imageUrl: image, heroTag: heroTag),
                  ),
                ),
        child: SizedBox(
          width: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: RoundedHero(tag: heroTag, child: AppImage(url: image, cacheWidth: 160)),
              ),
              const SizedBox(height: 4),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}
