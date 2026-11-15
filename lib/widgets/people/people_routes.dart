import 'package:flutter/material.dart';

import '../../screens/character_screen.dart';
import '../../screens/detail_screen.dart';
import '../../screens/staff_screen.dart';
import '../../screens/studio_screen.dart';
import '../../services/people_api.dart';

/// Opens the page of [staff]. With the [heroTag] of the photo that was
/// tapped (see `personHeroTag`), that photo flies there.
void openStaff(BuildContext context, StaffRef staff, {String? heroTag}) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffScreen(staffId: staff.id, name: staff.name, imageUrl: staff.imageUrl, heroTag: heroTag),
      ),
    );

/// Opens the page of [character]; [heroTag] as in [openStaff].
void openCharacter(BuildContext context, CharacterRef character, {String? heroTag}) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterScreen(
          characterId: character.id,
          name: character.name,
          imageUrl: character.imageUrl,
          heroTag: heroTag,
        ),
      ),
    );

/// Opens the detail page of [media] (anime or manga). With the [heroTag] of
/// the cover that was tapped (see `coverHeroTag`), that cover flies there.
void openMedia(BuildContext context, MediaRef media, {String? heroTag}) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(animeId: media.id, heroTag: heroTag, initialCoverUrl: media.coverUrl),
      ),
    );

/// Opens the page of the studio [studioId].
void openStudio(BuildContext context, int studioId, {String? name}) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudioScreen(studioId: studioId, name: name)),
    );
