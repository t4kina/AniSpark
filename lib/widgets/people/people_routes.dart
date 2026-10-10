import 'package:flutter/material.dart';

import '../../screens/character_screen.dart';
import '../../screens/detail_screen.dart';
import '../../screens/staff_screen.dart';
import '../../screens/studio_screen.dart';
import '../../services/people_api.dart';

/// Opens the page of [staff].
void openStaff(BuildContext context, StaffRef staff) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffScreen(staffId: staff.id, name: staff.name, imageUrl: staff.imageUrl),
      ),
    );

/// Opens the page of [character].
void openCharacter(BuildContext context, CharacterRef character) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterScreen(
          characterId: character.id,
          name: character.name,
          imageUrl: character.imageUrl,
        ),
      ),
    );

/// Opens the detail page of [media] (anime or manga).
void openMedia(BuildContext context, MediaRef media) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailScreen(animeId: media.id)),
    );

/// Opens the page of the studio [studioId].
void openStudio(BuildContext context, int studioId, {String? name}) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudioScreen(studioId: studioId, name: name)),
    );
