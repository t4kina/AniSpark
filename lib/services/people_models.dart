import 'package:flutter/foundation.dart' show immutable;

// Models behind PeopleApi; each mirrors one of its queries and doubles as
// its cache format.

T? _as<T>(Object? value) => value is T ? value : null;

/// A non-empty string, or null.
String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value : null;

/// `image { large medium }` → the best URL available.
String? _imageUrl(Object? image) =>
    image is Map ? _text(image['large']) ?? _text(image['medium']) : null;

bool _hasNextPage(Map json) {
  final pageInfo = json['pageInfo'];
  return pageInfo is Map && pageInfo['hasNextPage'] == true;
}

/// A date AniList may only know part of (its `FuzzyDate`).
@immutable
class FuzzyDate {
  const FuzzyDate({this.year, this.month, this.day});

  final int? year;

  /// 1–12.
  final int? month;

  /// 1–31.
  final int? day;

  /// Null when nothing is known; out-of-range months and days are dropped.
  static FuzzyDate? fromJson(Object? json) {
    if (json is! Map) return null;
    final year = _as<int>(json['year']);
    final month = _as<int>(json['month']);
    final day = _as<int>(json['day']);
    final validMonth = month != null && month >= 1 && month <= 12 ? month : null;
    final validDay = day != null && day >= 1 && day <= 31 ? day : null;
    if (year == null && validMonth == null && validDay == null) return null;
    return FuzzyDate(year: year, month: validMonth, day: validDay);
  }

  Map<String, dynamic> toJson() => {'year': year, 'month': month, 'day': day};
}

/// A media as listed on staff, studio and character pages.
@immutable
class MediaRef {
  const MediaRef({
    required this.id,
    this.type,
    this.format,
    this.isAdult = false,
    this.title = const {},
    this.coverUrl,
    this.startYear,
    this.averageScore,
  });

  final int id;

  /// `ANIME` or `MANGA`.
  final String? type;

  /// AniList's MediaFormat (TV, MOVIE, MANGA, NOVEL…).
  final String? format;
  final bool isAdult;

  /// The `romaji`/`english`/`native` titles AniList has, for
  /// `SettingsProvider.resolveTitle`.
  final Map<String, String> title;
  final String? coverUrl;
  final int? startYear;

  /// 0–100.
  final int? averageScore;

  bool get isManga => type == 'MANGA';

  /// Parses a media node; null without an id.
  static MediaRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _as<int>(json['id']);
    if (id == null) return null;
    final title = json['title'];
    final startDate = json['startDate'];
    return MediaRef(
      id: id,
      type: _text(json['type']),
      format: _text(json['format']),
      isAdult: json['isAdult'] == true,
      title: Map.unmodifiable({
        if (title is Map)
          for (final key in const ['romaji', 'english', 'native'])
            if (_text(title[key]) case final String value) key: value,
      }),
      coverUrl: _imageUrl(json['coverImage']),
      startYear: startDate is Map ? _as<int>(startDate['year']) : null,
      averageScore: _as<int>(json['averageScore']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'format': format,
        'isAdult': isAdult,
        'averageScore': averageScore,
        'title': title,
        'coverImage': {'large': coverUrl},
        'startDate': {'year': startYear},
      };
}

/// A staff member (voice actor, director, mangaka…) shown as a link.
@immutable
class StaffRef {
  const StaffRef({required this.id, required this.name, this.imageUrl, this.language});

  final int id;
  final String name;
  final String? imageUrl;

  /// AniList's `languageV2` in English ("Japanese", "English"…), for voice
  /// actors.
  final String? language;

  /// Parses `{ id name { full } image { large|medium } languageV2 }`; null
  /// without an id or a name.
  static StaffRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _as<int>(json['id']);
    final name = json['name'];
    final full = name is Map ? _text(name['full']) : null;
    if (id == null || full == null) return null;
    return StaffRef(
      id: id,
      name: full,
      imageUrl: _imageUrl(json['image']),
      language: _text(json['languageV2']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': {'full': name},
        'image': {'large': imageUrl},
        'languageV2': language,
      };
}

/// A character shown as a link.
@immutable
class CharacterRef {
  const CharacterRef({required this.id, required this.name, this.imageUrl});

  final int id;
  final String name;
  final String? imageUrl;

  /// Parses `{ id name { full } image { large|medium } }`; null without an
  /// id or a name.
  static CharacterRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _as<int>(json['id']);
    final name = json['name'];
    final full = name is Map ? _text(name['full']) : null;
    if (id == null || full == null) return null;
    return CharacterRef(id: id, name: full, imageUrl: _imageUrl(json['image']));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': {'full': name},
        'image': {'large': imageUrl},
      };
}

/// A character a voice actor played and the media it's from.
@immutable
class VoicedCharacter {
  const VoicedCharacter({required this.character, required this.media, this.role});

  final CharacterRef character;
  final MediaRef media;

  /// AniList's CharacterRole: MAIN, SUPPORTING or BACKGROUND.
  final String? role;
}

/// [shown] followed by the characters of [next] that aren't in it yet; a
/// character voiced in several media is listed once, with its most popular.
List<VoicedCharacter> appendVoicedCharacters(List<VoicedCharacter> shown, List<VoicedCharacter> next) {
  final seen = {for (final item in shown) item.character.id};
  return List.unmodifiable([
    ...shown,
    for (final item in next)
      if (seen.add(item.character.id)) item,
  ]);
}

/// One page of the characters a staff member voiced.
@immutable
class VoicedCharactersPage {
  const VoicedCharactersPage({required this.items, required this.hasNextPage});

  static const empty = VoicedCharactersPage(items: [], hasNextPage: false);

  final List<VoicedCharacter> items;
  final bool hasNextPage;

  /// Parses a `characterMedia` connection, skipping adult media and
  /// malformed edges; anything unreadable is an empty last page.
  static VoicedCharactersPage fromJson(Object? json) {
    if (json is! Map) return empty;
    final edges = json['edges'];
    final items = <VoicedCharacter>[];
    if (edges is List) {
      for (final edge in edges) {
        if (edge is! Map) continue;
        final media = MediaRef.fromJson(edge['node']);
        final characters = edge['characters'];
        if (media == null || media.isAdult || characters is! List) continue;
        final role = _text(edge['characterRole']);
        for (final character in characters) {
          final parsed = CharacterRef.fromJson(character);
          if (parsed != null) items.add(VoicedCharacter(character: parsed, media: media, role: role));
        }
      }
    }
    return VoicedCharactersPage(
      items: appendVoicedCharacters(const [], items),
      hasNextPage: _hasNextPage(json),
    );
  }

  Map<String, dynamic> toJson() => {
        'pageInfo': {'hasNextPage': hasNextPage},
        'edges': [
          for (final item in items)
            {
              'characterRole': item.role,
              'node': item.media.toJson(),
              'characters': [item.character.toJson()],
            },
        ],
      };
}

/// What a staff member did on a media ("Director", "Theme Song
/// Performance (OP)"…).
@immutable
class StaffRole {
  const StaffRole({required this.media, this.roles = const []});

  final MediaRef media;
  final List<String> roles;

  StaffRole _withRoles(List<String> more) => StaffRole(
        media: media,
        roles: List.unmodifiable([
          ...roles,
          for (final role in more)
            if (!roles.contains(role)) role,
        ]),
      );
}

/// [shown] followed by [next], merging the roles of a media that is already
/// listed (AniList returns one edge per role, possibly across pages).
List<StaffRole> appendStaffRoles(List<StaffRole> shown, List<StaffRole> next) {
  // Map literals keep insertion order, and replacing a value keeps its place.
  final byMedia = {for (final item in shown) item.media.id: item};
  for (final item in next) {
    final existing = byMedia[item.media.id];
    byMedia[item.media.id] = existing == null ? item : existing._withRoles(item.roles);
  }
  return List.unmodifiable(byMedia.values);
}

/// One page of a staff member's credits.
@immutable
class StaffRolesPage {
  const StaffRolesPage({required this.items, required this.hasNextPage});

  static const empty = StaffRolesPage(items: [], hasNextPage: false);

  final List<StaffRole> items;
  final bool hasNextPage;

  /// Parses a `staffMedia` connection, grouping the roles of each media and
  /// skipping adult media and malformed edges.
  static StaffRolesPage fromJson(Object? json) {
    if (json is! Map) return empty;
    final edges = json['edges'];
    final credits = <StaffRole>[];
    if (edges is List) {
      for (final edge in edges) {
        if (edge is! Map) continue;
        final media = MediaRef.fromJson(edge['node']);
        if (media == null || media.isAdult) continue;
        credits.add(StaffRole(media: media, roles: [?_text(edge['staffRole'])]));
      }
    }
    return StaffRolesPage(items: appendStaffRoles(const [], credits), hasNextPage: _hasNextPage(json));
  }

  Map<String, dynamic> toJson() => {
        'pageInfo': {'hasNextPage': hasNextPage},
        'edges': [
          for (final item in items)
            if (item.roles.isEmpty)
              {'staffRole': null, 'node': item.media.toJson()}
            else
              for (final role in item.roles) {'staffRole': role, 'node': item.media.toJson()},
        ],
      };
}

/// A staff member's page.
@immutable
class StaffDetail {
  const StaffDetail({
    required this.id,
    required this.name,
    this.nativeName,
    this.imageUrl,
    this.description,
    this.occupations = const [],
    this.gender,
    this.age,
    this.dateOfBirth,
    this.dateOfDeath,
    this.yearsActive = const [],
    this.homeTown,
    this.bloodType,
    this.favourites,
    this.characters = VoicedCharactersPage.empty,
    this.roles = StaffRolesPage.empty,
  });

  final int id;

  /// Empty when AniList has no name.
  final String name;
  final String? nativeName;
  final String? imageUrl;

  /// Raw AniList markdown; see `cleanReviewText` for display.
  final String? description;

  /// Free text from AniList ("Voice Actor", "Director"…).
  final List<String> occupations;

  /// Free text; usually Male, Female or Non-binary.
  final String? gender;
  final int? age;
  final FuzzyDate? dateOfBirth;
  final FuzzyDate? dateOfDeath;

  /// `[start]` while active, `[start, end]` once retired.
  final List<int> yearsActive;
  final String? homeTown;
  final String? bloodType;
  final int? favourites;

  /// The first page of each list.
  final VoicedCharactersPage characters;
  final StaffRolesPage roles;

  /// Parses a `Staff` (same shape as [toJson]); null without an id.
  static StaffDetail? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _as<int>(json['id']);
    if (id == null) return null;
    final name = json['name'];
    final occupations = json['primaryOccupations'];
    final yearsActive = json['yearsActive'];
    return StaffDetail(
      id: id,
      name: (name is Map ? _text(name['full']) : null) ?? '',
      nativeName: name is Map ? _text(name['native']) : null,
      imageUrl: _imageUrl(json['image']),
      description: _text(json['description']),
      occupations: List.unmodifiable([
        if (occupations is List)
          for (final occupation in occupations) ?_text(occupation),
      ]),
      gender: _text(json['gender']),
      age: _as<int>(json['age']),
      dateOfBirth: FuzzyDate.fromJson(json['dateOfBirth']),
      dateOfDeath: FuzzyDate.fromJson(json['dateOfDeath']),
      yearsActive: List.unmodifiable([
        if (yearsActive is List)
          for (final year in yearsActive) ?_as<int>(year),
      ]),
      homeTown: _text(json['homeTown']),
      bloodType: _text(json['bloodType']),
      favourites: _as<int>(json['favourites']),
      characters: VoicedCharactersPage.fromJson(json['characterMedia']),
      roles: StaffRolesPage.fromJson(json['staffMedia']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': {'full': name, 'native': nativeName},
        'image': {'large': imageUrl},
        'description': description,
        'primaryOccupations': occupations,
        'gender': gender,
        'age': age,
        'dateOfBirth': dateOfBirth?.toJson(),
        'dateOfDeath': dateOfDeath?.toJson(),
        'yearsActive': yearsActive,
        'homeTown': homeTown,
        'bloodType': bloodType,
        'favourites': favourites,
        'characterMedia': characters.toJson(),
        'staffMedia': roles.toJson(),
      };
}

/// [shown] followed by the media of [next] that aren't in it yet (rankings
/// can shift between pages).
List<MediaRef> appendMedia(List<MediaRef> shown, List<MediaRef> next) {
  final seen = {for (final media in shown) media.id};
  return List.unmodifiable([
    ...shown,
    for (final media in next)
      if (seen.add(media.id)) media,
  ]);
}

/// One page of media.
@immutable
class MediaPage {
  const MediaPage({required this.media, required this.hasNextPage});

  static const empty = MediaPage(media: [], hasNextPage: false);

  final List<MediaRef> media;
  final bool hasNextPage;

  /// Parses `{ pageInfo { hasNextPage } nodes {…} }`, skipping adult and
  /// malformed nodes.
  static MediaPage fromJson(Object? json) {
    if (json is! Map) return empty;
    final nodes = json['nodes'];
    return MediaPage(
      media: List.unmodifiable([
        if (nodes is List)
          for (final node in nodes)
            if (MediaRef.fromJson(node) case final MediaRef media when !media.isAdult) media,
      ]),
      hasNextPage: _hasNextPage(json),
    );
  }

  Map<String, dynamic> toJson() => {
        'pageInfo': {'hasNextPage': hasNextPage},
        'nodes': [for (final item in media) item.toJson()],
      };
}

/// A studio's page.
@immutable
class StudioDetail {
  const StudioDetail({
    required this.id,
    required this.name,
    this.isAnimationStudio = false,
    this.favourites,
    this.main = MediaPage.empty,
    this.other = MediaPage.empty,
  });

  final int id;

  /// Empty when AniList has no name.
  final String name;

  /// False for producers, licensors…
  final bool isAnimationStudio;
  final int? favourites;

  /// First pages of the media it was the main studio of, and of the rest.
  final MediaPage main;
  final MediaPage other;

  /// Parses a `Studio` with `main`/`other` media aliases (same shape as
  /// [toJson]); null without an id.
  static StudioDetail? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _as<int>(json['id']);
    if (id == null) return null;
    return StudioDetail(
      id: id,
      name: _text(json['name']) ?? '',
      isAnimationStudio: json['isAnimationStudio'] == true,
      favourites: _as<int>(json['favourites']),
      main: MediaPage.fromJson(json['main']),
      other: MediaPage.fromJson(json['other']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isAnimationStudio': isAnimationStudio,
        'favourites': favourites,
        'main': main.toJson(),
        'other': other.toJson(),
      };
}

/// A character's page.
@immutable
class CharacterDetail {
  const CharacterDetail({
    required this.id,
    required this.name,
    this.isFavourite = false,
    this.nativeName,
    this.imageUrl,
    this.description,
    this.gender,
    this.age,
    this.bloodType,
    this.dateOfBirth,
    this.media = const [],
    this.voiceActors = const [],
  });

  final int id;

  /// Empty when AniList has no name.
  final String name;

  /// Whether the viewer favourited it (false when logged out).
  final bool isFavourite;
  final String? nativeName;
  final String? imageUrl;

  /// Raw AniList markdown; see `cleanReviewText` for display.
  final String? description;

  /// Free text; usually Male, Female or Non-binary.
  final String? gender;

  /// Free text ("17", "17-18", "Unknown"…).
  final String? age;
  final String? bloodType;
  final FuzzyDate? dateOfBirth;

  /// Its most popular appearances, adult media left out.
  final List<MediaRef> media;

  /// Everyone who voiced it in [media], each once, Japanese first.
  final List<StaffRef> voiceActors;

  CharacterDetail copyWith({bool? isFavourite}) => CharacterDetail(
        id: id,
        name: name,
        isFavourite: isFavourite ?? this.isFavourite,
        nativeName: nativeName,
        imageUrl: imageUrl,
        description: description,
        gender: gender,
        age: age,
        bloodType: bloodType,
        dateOfBirth: dateOfBirth,
        media: media,
        voiceActors: voiceActors,
      );

  /// Parses a `Character` from the API (voice actors on `media.edges`) or
  /// as saved by [toJson] (top-level `voiceActors`, `media.nodes`); null
  /// without an id.
  static CharacterDetail? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _as<int>(json['id']);
    if (id == null) return null;
    final name = json['name'];
    final connection = json['media'];
    final edges = connection is Map ? connection['edges'] : null;
    final nodes = connection is Map ? connection['nodes'] : null;
    final media = <MediaRef>[];
    final actors = <StaffRef>[];
    if (edges is List) {
      for (final edge in edges) {
        if (edge is! Map) continue;
        final node = MediaRef.fromJson(edge['node']);
        if (node == null || node.isAdult) continue;
        media.add(node);
        final voiceActors = edge['voiceActors'];
        if (voiceActors is List) actors.addAll([for (final actor in voiceActors) ?StaffRef.fromJson(actor)]);
      }
    } else if (nodes is List) {
      media.addAll([
        for (final node in nodes)
          if (MediaRef.fromJson(node) case final MediaRef item when !item.isAdult) item,
      ]);
    }
    final savedActors = json['voiceActors'];
    if (savedActors is List) actors.addAll([for (final actor in savedActors) ?StaffRef.fromJson(actor)]);
    final seenActors = <int>{};
    return CharacterDetail(
      id: id,
      name: (name is Map ? _text(name['full']) : null) ?? '',
      isFavourite: json['isFavourite'] == true,
      nativeName: name is Map ? _text(name['native']) : null,
      imageUrl: _imageUrl(json['image']),
      description: _text(json['description']),
      gender: _text(json['gender']),
      age: _text(json['age']),
      bloodType: _text(json['bloodType']),
      dateOfBirth: FuzzyDate.fromJson(json['dateOfBirth']),
      media: List.unmodifiable(media),
      voiceActors: sortVoiceActors([
        for (final actor in actors)
          if (seenActors.add(actor.id)) actor,
      ]),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'isFavourite': isFavourite,
        'name': {'full': name, 'native': nativeName},
        'image': {'large': imageUrl},
        'description': description,
        'gender': gender,
        'age': age,
        'bloodType': bloodType,
        'dateOfBirth': dateOfBirth?.toJson(),
        'media': {
          'nodes': [for (final item in media) item.toJson()],
        },
        'voiceActors': [for (final actor in voiceActors) actor.toJson()],
      };
}

/// [actors] with the Japanese cast first, then those dubbing in
/// [preferredLanguage] (an AniList `languageV2` such as "Spanish"), then the
/// rest, each group in its original order.
List<StaffRef> sortVoiceActors(List<StaffRef> actors, {String? preferredLanguage}) {
  final preferred = preferredLanguage?.toLowerCase();
  int rank(StaffRef actor) {
    final language = actor.language?.toLowerCase();
    if (language == 'japanese') return 0;
    if (language != null && language == preferred) return 1;
    return 2;
  }

  // Grouping by rank keeps each group's order (List.sort isn't stable).
  return List.unmodifiable([
    for (var group = 0; group <= 2; group++) ...actors.where((actor) => rank(actor) == group),
  ]);
}

/// A staff member credited on a media, with every role they had on it.
@immutable
class StaffCredit {
  const StaffCredit({required this.staff, this.roles = const []});

  final StaffRef staff;
  final List<String> roles;

  /// Parses the detail query's `staff { edges { role node {…} } }` edges,
  /// listing each person once with their roles merged and skipping
  /// malformed edges.
  static List<StaffCredit> listFromEdges(Object? edges) {
    if (edges is! List) return const [];
    final byStaff = <int, StaffCredit>{};
    for (final edge in edges) {
      if (edge is! Map) continue;
      final staff = StaffRef.fromJson(edge['node']);
      if (staff == null) continue;
      final role = _text(edge['role']);
      final existing = byStaff[staff.id];
      final roles = existing?.roles ?? const <String>[];
      byStaff[staff.id] = StaffCredit(
        staff: existing?.staff ?? staff,
        roles: List.unmodifiable([...roles, if (role != null && !roles.contains(role)) role]),
      );
    }
    return List.unmodifiable(byStaff.values);
  }
}

/// A studio credited on a media.
@immutable
class StudioRef {
  const StudioRef({this.id, required this.name, this.isAnimationStudio = false});

  /// Null when the query didn't ask for it; the studio can't be opened then.
  final int? id;
  final String name;
  final bool isAnimationStudio;

  /// Parses `studios { nodes { id name isAnimationStudio } }` nodes (or
  /// `edges { node {…} }`), skipping nameless ones and repeats.
  static List<StudioRef> listFromJson(Object? nodes) {
    if (nodes is! List) return const [];
    final studios = <StudioRef>[];
    final seen = <Object>{};
    for (final raw in nodes) {
      final node = raw is Map && raw['node'] is Map ? raw['node'] as Map : raw;
      if (node is! Map) continue;
      final name = _text(node['name']);
      final id = _as<int>(node['id']);
      if (name == null || !seen.add(id ?? name)) continue;
      studios.add(StudioRef(id: id, name: name, isAnimationStudio: node['isAnimationStudio'] == true));
    }
    return List.unmodifiable(studios);
  }
}
